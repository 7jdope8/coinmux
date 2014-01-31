class Cli::Application
  include Coinmux::BitcoinUtil, Coinmux::Facades

  attr_accessor :participant, :director, :notification_callback
  attr_accessor :amount, :participants, :input_private_key, :output_address, :change_address, :coin_join_uri

  def initialize(options = {})
    options.assert_keys!(required: [:amount, :participants, :input_private_key, :output_address, :change_address], optional: [:coin_join_uri, :list])

    self.amount = (options[:amount].to_f * SATOSHIS_PER_BITCOIN).to_i
    self.participants = options[:participants].to_i
    self.input_private_key = options[:input_private_key]
    self.output_address = options[:output_address]
    self.change_address = options[:change_address]
    self.coin_join_uri = options[:coin_join_uri] || Coinmux::Config.instance.coin_join_uri
  end

  def list_coin_joins
    data_store.startup

    data_store.fetch_most_recent(data_store.coin_join_identifier, Coinmux::StateMachine::Participant::COIN_JOIN_MESSAGE_FETCH_SIZE) do |event|
      if event.error
        raise event.error
      else
        coin_join_messages = event.data.collect { |json| Coinmux::Message::CoinJoin.from_json(json, data_store, nil) }.compact

        available_coin_joins = []
        if !coin_join_messages.empty?
          waiting_for = coin_join_messages.size
          coin_join_messages.each do |coin_join_message|
            coin_join_message.status.refresh do |event|
              if event.error
                raise event.error
              else
                if coin_join_message.status.value.status != 'waiting_for_inputs'
                  waiting_for -= 1
                else
                  coin_join_message.inputs.refresh do |event|
                    if event.error
                      raise event.error
                    else
                      available_coin_joins << {
                        amount: coin_join_message.amount,
                        total_participants: coin_join_message.participants,
                        waiting_participants: coin_join_message.inputs.value.size
                      }
                      waiting_for -= 1
                    end
                  end
                end
              end
            end
          end

          while waiting_for > 0
            sleep(0.1)
          end
        end

        if available_coin_joins.empty?
          puts "No available CoinJoins"
        else
          puts("%10s  %12s" % ["BTC Amount", "Participants"])
          puts "#{'=' * 10}  #{'=' * 12}"
          available_coin_joins.sort { |l, r| l[:amount] <=> r[:amount] }.each do |hash|
            puts "%-10s  %-12s" % [hash[:amount].to_f / SATOSHIS_PER_BITCOIN, "#{hash[:waiting_participants]} of #{hash[:total_participants]}"]
          end
        end
      end
    end

    data_store.shutdown
  end

  def start
    if self.input_private_key.blank?
      puts "Enter your private key (HEX format):"
      self.input_private_key = $stdin.readline.strip
    end

    info "Starting CLI application"

    if (input_errors = validate_inputs).present?
      message "Unable to perform CoinJoin due to the following:"
      message input_errors.collect { |message| " * #{message}" }
      message "Quitting..."
      return
    end

    self.notification_callback = Proc.new do |event|
      debug "event queue event received: #{event.inspect}"
      if event.type == :failed
        message "Error - #{event.message}", event.source
        message "Quitting..."
        self.director = self.participant = nil # end execution
      else
        message "#{event.type.to_s.humanize.capitalize}#{" - #{event.message}" if event.message}", event.source
        if event.source == :participant
          handle_participant_event(event)
        elsif event.source == :director
          handle_director_event(event)
        else
          raise "Unknown event source: #{event.source}"
        end
      end

      if participant.nil? && director.nil?
        # we are done, so notify the event queue to complete
        Cli::EventQueue.instance.stop
      end
    end

    data_store.startup

    Cli::EventQueue.instance.start

    self.participant = build_participant
    participant.start(&notification_callback)

    Cli::EventQueue.instance.wait

    data_store.shutdown
  end

  private

  def message(messages, event_type = nil)
    messages = [messages] unless messages.is_a?(Array)
    messages.each do |message|
      if event_type
        puts "%14s %s" % ['[' + event_type.to_s.capitalize + ']:', message]
      else
        puts message
      end
    end
  end

  def validate_inputs
    errors = []

    begin
      Coinmux::CoinJoinUri.parse(coin_join_uri)
    rescue Coinmux::Error => e
      errors << "CoinJoin URI is invalid"
    end

    coin_join = Coinmux::Message::CoinJoin.build(data_store, amount: amount, participants: participants)
    errors += coin_join.errors.full_messages unless coin_join.valid?

    input = Coinmux::Message::Input.build(coin_join, private_key: input_private_key, change_address: change_address)
    input.valid?
    errors += input.errors[:address].collect { |e| "Input address #{e}" } unless input.errors[:address].blank?
    errors += input.errors[:change_address].collect { |e| "Change address #{e}" } unless input.errors[:change_address].blank?

    output = Coinmux::Message::Output.build(coin_join, address: output_address)
    output.valid?
    errors += output.errors[:address].collect { |e| "Output address #{e}" } unless output.errors[:address].blank?

    errors
  end

  def data_store
    @data_store ||= Coinmux::DataStore::Factory.build(Coinmux::CoinJoinUri.parse(coin_join_uri))
  end

  def build_participant
    Coinmux::StateMachine::Participant.new(
      event_queue: Cli::EventQueue.instance,
      data_store: data_store,
      amount: amount,
      participants: participants,
      input_private_key: input_private_key,
      output_address: output_address,
      change_address: change_address)
  end

  def build_director
    Coinmux::StateMachine::Director.new(
      event_queue: Cli::EventQueue.instance,
      data_store: data_store,
      amount: amount,
      participants: participants)
  end

  def handle_participant_event(event)
    if [:no_available_coin_join].include?(event.type)
      if director.nil?
        # start our own Director since we couldn't find one
        self.director = build_director
        director.start(&notification_callback)
      end
    elsif [:input_not_selected, :transaction_not_found].include?(event.type)
      # TODO: try again
    elsif event.type == :completed
      self.participant = nil # done
      message "CoinJoin successfully created!"
    elsif event.type == :failed
      self.participant = nil # done
      message "CoinJoin failed!"
    end
  end

  def handle_director_event(event)
    if event.type == :waiting_for_inputs
      # our Director is now ready, so let's get started with a new participant
      self.participant = build_participant
      participant.start(&notification_callback)
    elsif event.type == :failed || event.type == :completed
      self.director = nil # done
    end
  end
end
