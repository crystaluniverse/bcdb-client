# bcdb-client

Rest client for [BCDB](https://github.com/threefoldtech/bcdb)

## Run tests
- `crystal spec spec/bcdb-client_spec.cr`

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     bcdb:
       github: crystaluniverse/bcdb-client
   ```

2. Run `shards install`

## Usage

### Download, compile & run 0-db (Backend for BCDB)
- `git clone git@github.com:threefoldtech/0-db.git`
- `cd 0-db && make`
- `./zdb --mode seq`

### Download, compile & run BCDB (Backend for BCDB)
- Install [Rust programming language](https://www.rust-lang.org/tools/install)
- `git clone git@github.com:threefoldtech/bcdb.git`
- `cd bcdb && make`
- copy bcdb binary anywhere `cp bcdb/target/x86_64-unknown-linux-musl/release/bcdb .`
- download `tfuser` utility from [here](https://github.com/crystaluniverse/bcdb-client/releases/download/v0.1/tfuser)
- use `tfuser` to register your 3bot user to explorer and generate seed file `usr.seed` using `./tfuser id create --name {3bot_username.3bot} --email {email}`
- run bcdb : `./bcdb --seed-file user.seed `
- now you can talk to `bcdb` through http via unix socket `/tmp/bcdb.sock`

### Copy zdb and bcdb to your local user **Optional**
- You can copy zdb and bcdb to _/usr/local/bin_ to be able to use them from terminal directly as follow:
  - `sudo cp {0-db folder path}/bin/zdb /usr/local/bin`
  - `sudo cp {bcdb folder path}/target/x86_64-unknown-linux-musl/release/bcdb /usr/local/bin`
- Now you can use them as follow:
  - For 0-db: `zdb --mode seq --data {path to data folder} --index {path to index folder}`
  
  > You have to choose the path of data and index folders as you prefer, the default path is the same folder zdb run from. 
  
  - For bcdb: `bcdb --seed-file user.seed`

### Use the library in your application

**WARNING**

bcdb can have currently one database called `db` any attempt to use a different db name will fail, but you can freely use any `namespace` name you'd like

```crystal
require "bcdb"

c = Bcdb::Client.new unixsocket: "/tmp/bcdb.sock", db: "db", namespace: "example" 
tags = {"example" => "value", "tag2" => "v2"}
# PUT
key = c.put("a", tags)

# GET
res = c.get(key)
res["data"].should eq "a"
res["tags"]["example"].should eq "value"
res["tags"]["tag2"].should eq "v2"

# UPDATE
c.update(key, "b", tags)

res = c.get(key)
res["data"].should eq "b"
res["tags"]["example"].should eq "value"
res["tags"]["tag2"].should eq "v2"

# Delete
c.delete(key)
c.get(key)  =>  Bcdb::NotFoundError

# find
res = c.find({"example" => "value"})
puts res => [1,2,3] 

# Acls

acl = client.acl.set("r--", [1,2])
res = client.acl.get(acl)
pp! res => {"permission" => "r--", "users" => [1, 2]}

client.acl.update(acl, "rwd")
client.acl.grant(acl, [3,4])
client.acl.revoke(acl, [1,4])
res = client.acl.get(acl)
pp! res => {"permission" => "r--", "users" => [2, 3]}

client.acl.list => [{"id" => 0, "permission" => "r--", "users" => [1, 2]}]

# Put & Update with Acls

key_acl = c.put value: "b", tags: tags, acl: acl
res_acl = c.get(key_acl)
res_acl["tags"][":acl"].should eq acl.to_s

new_acl = c.acl.set("rwd", [5,6])
c.update key: key_acl, value: "b", tags: tags, acl: new_acl
res_acl = c.get(key_acl)
res_acl["tags"][":acl"].should eq new_acl.to_s

```
# BCDB cluster (With an Example)
all APIs take an optional `threebot_id` if you want the local bcdb to delegate requests to another bcdb


## Register 2 users on explorer**

- **User 1**
  - `./tfuser id create --name bcdbchat1.3bot --email bcdbchat1@threefold.io --output bcdbchat1.seed --description Bcdb test user`
    ```
    1:50PM INF generating seed mnemonic
    1:50PM INF writing user identity filename=bcdbchat1.seed
    Your ID is: 1607
    ```

  - Get info for this user `curl -X GET "https://explorer.devnet.grid.tf/explorer/users/1607" -H  "accept: application/json"`
    ```
    {"id":1607,"name":"bcdbchat1.3bot","email":"","pubkey":"0bcc59ed4d5967cebcf5fb7928433aa31735d1c3be25e489d08406034dc01479","host":"","description":""}
    ```
- - **User 2**
  - `./tfuser id create --name bcdbchat2.3bot --email bcdbchat2@threefold.io --output bcdbchat2.seed --description Bcdb test user2 `
    ```
    1:50PM INF generating seed mnemonic
    1:50PM INF writing user identity filename=bcdbchat2.seed
    Your ID is: 1608
    ```
  - Get info for this user `curl -X GET "https://explorer.devnet.grid.tf/explorer/users/1608" -H  "accept: application/json"`
    ```
    {"id":1608,"name":"bcdbchat2.3bot","email":"","pubkey":"f4594db450f067ea6489ad6804917858845e44fad8d0a531188b06b10b7bb707","host":"","description":""}
    ```

## Create peers file `peers.json`
resolving `threebot_ids` should be done by explorer, however we use `peers.json` file to resolve the hosts of bcdb, it's similar to local dns cache, because at the moment explorer has an issue keeping the hosts 

  ```
  {"id":1607,"name":"bcdbchat1.3bot","email":"","pubkey":"0bcc59ed4d5967cebcf5fb7928433aa31735d1c3be25e489d08406034dc01479","host":"http://localhost:50051","description":""}
  {"id":1608,"name":"bcdbchat2.3bot","email":"","pubkey":"f4594db450f067ea6489ad6804917858845e44fad8d0a531188b06b10b7bb707", "host":"http://localhost:50052","description":""}
  ```

## Run

**Node 1**
- zdb : `./zdb --mode seq --data .zdb1/data --index ./zdb1/index`
- bcdb: `./bcdb -r ./bcdb1.sock -m .meta/bcdb1.meta --seed-file bcdbchat1.seed --peers-file peers.json `

**Node 2**
- zdb : `./zdb --mode seq --data .zdb2/data --index ./zdb2/index --port 9901`
- bcdb: `./bcdb -r ./bcdb2.sock -m .meta/bcdb2.meta --seed-file bcdbchat2.seed --peers-file peers.json -z 9901 -g 0.0.0.0:50052`

## Testing

This test is not included in the spec file, because it needs special cluster running which will lead this test to fail usually unless cluster is up and running

  ```crystal
  it "cluster" do
      node1 = Bcdb::Client.new unixsocket: "/home/hamdy/work/chat/bcdb1.sock", db: "db", namespace: "example" 
      key = node1.put("Hello world!")
      node1.get(key)["data"].should eq "Hello world!"
      node2 = Bcdb::Client.new unixsocket: "/home/hamdy/work/chat/bcdb2.sock", db: "db", namespace: "example"
      begin
        value = node2.get key: key, threebot_id: "1607"
        raise "Should have raised exception"
      rescue Bcdb::UnAuthorizedError; end

      acl = node1.acl.set("r--", [1608])
      key = node1.put value: "Hello world!", acl: acl
      node2 = Bcdb::Client.new unixsocket: "/home/hamdy/work/chat/bcdb2.sock", db: "db", namespace: "example"
      value = node2.get key: key, threebot_id: "1607"
      
      begin
        value = node2.get key: key, threebot_id: "1607"
      rescue Bcdb::UnAuthorizedError
        raise "Should not have raised exception"
      end
    end
    ```