require "./spec_helper"
require "json"

describe Bcdb::Client do
  it "works" do
    
    c = Bcdb::Client.new unixsocket: "/tmp/bcdb.sock", db: "db", namespace: "example" 
    tags = {"example" => "value", "tag2" => "v2"}
    key = c.put("a", tags)
    
    res = c.get(key)
    res["data"].should eq "a"
    res["tags"]["example"].should eq "value"
    res["tags"]["tag2"].should eq "v2"

    c.update(key, "b", tags)

    res = c.get(key)
    res["data"].should eq "b"
    res["tags"]["example"].should eq "value"
    res["tags"]["tag2"].should eq "v2"

    begin
      c.get(1100)
      raise "Should have raised exception"
    rescue exception
    end


  end
end
