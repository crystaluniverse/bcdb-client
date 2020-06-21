require "crest"
require "json"
require "mnemonic"

module Bcdb 
  class Client
    property url : String
    property threebot_id : Int32
    property seed_phrase : String
    property auth_header : String
    property expires : Int32

    def initialize(@url, @threebot_id, @seed_phrase, @expires=2)
      en = Mnemonic::Mnemonic.new
      sk = en.get_signing_key @seed_phrase
      created = Time.utc.to_unix
      expires = created + @expires
      headers = %((created): #{created}\n)
      headers += %((expires): #{expires}\n)
      headers += %((key-id): #{@threebot_id})
      signature = Base64.strict_encode(String.new sk.sign_detached(headers))
      @auth_header = %(Signature keyId="#{@threebot_id}",algorithm="hs2019",created="#{created}",expires="#{expires}",headers="(created) (expires) (key-id)",signature="#{signature}")
    end


    def put(key : String, value : String)
      resp = Crest.post(
        @url,
        form: value,
        headers: {
          "Content-Type" => "application/json",
          "authorization" => @auth_header
        })
      resp.body.to_i32
    end
  
    def get(id : Int32)
      resp = Crest.get(@url + "/" + id.to_s,
        headers: {
          "Content-Type" => "application/json",
          "Authorization" => @auth_header
        })
      resp.body
    end
      

  end

  


end
