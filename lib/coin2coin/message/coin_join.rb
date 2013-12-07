class Coin2Coin::Message::CoinJoin < Coin2Coin::Message::Base
  VERSION = 1
  
  property :version
  property :message_public_key
  property :amount
  property :minimum_size
  property :input_list
  property :input_alive_list
  property :message_verification_instance
  property :output_list
  property :transaction_instance
  property :status_queue
  
  attr_accessor :message_private_key
  
  def initialize(params = {:amount => nil, :minimum_size => nil})
    params.assert_valid_keys(:amount, :minimum_size)
    
    self.version = VERSION
    @message_private_key, self.message_public_key = Coin2Coin::PKI.generate_keypair
    self.amount = params[:amount]
    self.minimum_size = params[:minimum_size]
    self.input_list = Coin2Coin::Message::Association.new
    self.input_alive_list = Coin2Coin::Message::Association.new
    self.message_verification_instance = Coin2Coin::Message::Association.new(true)
    self.output_list = Coin2Coin::Message::Association.new
    self.transaction_instance = Coin2Coin::Message::Association.new(true)
    self.status_queue = Coin2Coin::Message::Association.new(true)
  end
end
