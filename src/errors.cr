class Bcdb::NoFreeConnectionsError < IO::Error; end

class Bcdb::NotFoundError < Exception
    def initialize (@err : String); end
end

class Bcdb::UnAuthorizedError < Exception 
    def initialize (@err : String); end
end  