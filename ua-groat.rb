# Incoming SMTP server for UA=IMAP using groat-smtpd

require 'rubygems'
require 'json'
require 'sha1'

require 'groat/smtpd/smtp'
require 'groat/smtpd/server'
require 'groat/smtpd/extensions/pipelining'
require 'groat/smtpd/extensions/eightbitmime'
require 'groat/smtpd/extensions/help'

class SMTPConnection < Groat::SMTPD::SMTP
    include Groat::SMTPD::Extensions::Pipelining
    include Groat::SMTPD::Extensions::EightBitMIME
    include Groat::SMTPD::Extensions::Help

    # We can't validate this yet because we have no idea who is sending this yet
    validate_mailfrom do |from|
        @validated_from = from
    end

    validate_rcptto do |recipient|
        puts *recipient.inspect

        # Check if our incoming reply-to address is valid for this user
        digest = 'nodigest'
        check = 'nocheck'

        # Only check the first recipient because we should only have one
        (localpart, domain) = recipient.split('@')
        (reply, user, mid, digest) = localpart.split('-')

        puts "lp=#{localpart}"

        if user.nil? or mid.nil? or digest.nil? then
            puts "? Invalid address, something is missing"
            self.response_no_valid_rcpt()
        end

        puts "JSON = /home/#{user}/.ua2md"

        begin
            user_config = JSON.load(File.open("/home/#{user}/.ua2md"))
            p user_config
            nonce = user_config['nonce']
            check = SHA1.hexdigest([mid, user, nonce].join('-'))[0..7]

            puts "[#{digest}] == [#{check}]"

            if digest != check then
                self.response_no_valid_rcpt()
            end

            "OK for UA posting"
        rescue => e
            puts e.inspect
            self.response_no_valid_rcpt()
        end
    end

    def deliver!
        puts "Envelope Sender: #{@mailfrom}"
        puts "Envelope Recipients: #{@rcptto.join(" ")}"
        puts "Message follows"
        puts @message
    end

    def send_greeting
        reply :code => 220, :message => "Welcome to the Groat example server"
    end

    def initialize
        @hostname = 'localhost'
        super
    end

end

s = Groat::SMTPD::Server.new SMTPConnection, 9025
s.start
s.join

