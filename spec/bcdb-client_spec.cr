require "./spec_helper"
require "json"
require "uuid"

describe Bcdb::Client do
  it "works" do

    
    client = Bcdb::Client.new unixsocket: "/tmp/bcdb.sock", db: "db", namespace: "example" 
    random_tag = "#{UUID.random.to_s}"
    tags = {"example" => random_tag, "tag2" => "v2"}
    
    key = client.put("a", tags)
    
    res = client.get(key)
    res["data"].should eq "a"
    res["tags"]["example"].should eq random_tag
    res["tags"]["tag2"].should eq "v2"

    client.update(key, "b", tags)

    res = client.get(key)
    res["data"].should eq "b"
    res["tags"]["example"].should eq random_tag
    res["tags"]["tag2"].should eq "v2"

    res = client.fetch(key)
    res["data"].should eq "b"
    res["tags"]["example"].should eq random_tag
    res["tags"]["tag2"].should eq "v2"

    res = client.find({"example" => random_tag})
    res.should eq [key]

    client.delete(key)
    begin
      res = client.get(key)
      raise "Should have raised exception"
    rescue exception
      Bcdb::NotFoundError
    end  
  end
end
