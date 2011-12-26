require 'json'
require 'sha1'
require 'mini-smtp-server'

class UASmtpServer < MiniSmtpServer
    def new_message_event(message)
      puts "# New email received:"
      puts "-- From: #{message_hash[:from]}"
      puts "-- To:   #{message_hash[:to]}"
      puts "--"
      puts "-- " + message_hash[:data].gsub(/\r\n/, "\r\n-- ")
      puts
    end
end

# Start our server on port 9025 for testing.
server = UASmtpServer.new(9025, '127.0.0.1', 4)
server.start
server.join
