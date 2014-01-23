require 'active_support/inflector'

class Coinmux::Message::Association < Coinmux::Message::Base
  attr_accessor :name, :type, :data_store_identifier_from_build, :data_store_identifier, :read_only

  validate :data_store_identifier_has_correct_permissions, :unless => :created_with_build?

  class << self
    def build(coin_join, name, type, read_only)
      message = build_without_associations(coin_join)
      message.name = name.to_s
      message.type = type
      message.read_only = read_only
      message.data_store_identifier_from_build = data_store_facade.generate_identifier
      message.data_store_identifier = read_only ?
        data_store_facade.convert_to_request_only_identifier(message.data_store_identifier_from_build) :
        message.data_store_identifier_from_build

      message
    end

    def from_data_store_identifier(data_store_identifier, coin_join, name, type, read_only)
      message = new
      message.coin_join = coin_join

      message.name = name.to_s
      message.type = type
      message.read_only = read_only
      message.data_store_identifier = data_store_identifier

      return nil unless message.valid?

      message
    end
  end

  def initialize
    @messages = []
  end

  def value
    result = if type == :list
      messages
    elsif type == :fixed
      messages.first
    elsif type == :variable
      messages.last
    else
      raise "Unexpected type: #{type.inspect}"
    end

    result
  end

  def messages
    @messages
  end

  def insert(message, &callback)
    @messages << message

    data_store_facade.insert(data_store_identifier_from_build || data_store_identifier, message.to_json) do |event|
      yield(event) if block_given?
    end
  end

  def refresh(&callback)
    args = {
      list: [:fetch_all, :plural],
      fixed: [:fetch_first, :singular],
      variable: [:fetch_last, :singular]
    }
    fetch_messages(*args[type]) do |event|
      yield(event) if block_given?
    end
  end

  # Note: messages are not directly retrieved since this would require a callback/blocking
  # Instead, there is another thread that updates the messages with this method
  def update_message_jsons(jsons)
    @messages = message_jsons.collect { |json| build_message(json) }.compact
  end

  private

  def fetch_messages(method, plurality, &callback)
    data_store_facade.send(method, data_store_identifier) do |event|
      if event.error
        yield(event)
      else
        @messages = if event.data.nil?
          []
        elsif plurality == :plural
          event.data.collect { |data| association_class.from_json(data, coin_join) }
        elsif plurality == :singular
          [association_class.from_json(event.data, coin_join)]
        end

        # ignore bad data returned by #from_json as nil with compact
        @messages.compact!

        yield(Coinmux::Event.new(data: plurality == :plural ? @messages : @messages.first))
      end
    end
  end

  def data_store_identifier_has_correct_permissions
    can_insert = data_store_facade.identifier_can_insert?(data_store_identifier.to_s)
    can_request = data_store_facade.identifier_can_request?(data_store_identifier.to_s)

    errors[:data_store_identifier] << "must allow requests" unless can_request
    if !read_only
      errors[:data_store_identifier] << "must allow inserts" if !can_insert
    end
  end

  def association_class
    Coinmux::Message.const_get(name.classify)
  end

  def build_message(json)
    association_class.from_json(json, coin_join)
  end
end
