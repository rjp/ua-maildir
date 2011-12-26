require 'rubygems'
require 'json'
require 'open-uri'
require 'rest_client'
require 'sha1'
require 'maildir'
require 'mail'

# Trivial implementation of a UA message class
class Message
    attr_accessor :unique_name, :folder
    attr_accessor :pid, :subject, :body, :parent
    attr_accessor :epoch, :from, :to

    # Turn a triplet of {message_id, username, nonce} into a digest suitable for authentication checking later.
    def reply_to(username, nonce)
        sha1 = SHA1.hexdigest([@pid, username, nonce].join('-'))
        return [username, @pid, sha1[0..7]].join('-')
    end
end
# Handy utility function to replaces dots with underscores
class String
    def to_email
        return "#{self} <user-#{self.gsub(/[^-A-Za-z0-9]/, "-").downcase}@ua.frottage.org>"
    end
    def nodots
        return self.gsub('.','_')
    end
    def sanitise
        return self.gsub(%r{[^a-zA-Z0-9]}, '_')
    end
end

# World's kludgiest constructor
def new_message(subject, from, to, body, id, folder, epoch, parent)
    message = Message.new
    message.subject = subject
    message.from = from
    message.to = to
    message.body = body
    message.pid = id
    message.folder = folder
    message.epoch = epoch
    message.parent = parent
    return message
end

# Configuration - move this to a YAML or JSON file
$config = JSON.load(File.open(ENV['HOME'] + '/.ua2md'))

$ua_username = $config['username'] || ENV['USER']
$ua_password = $config['password']
$subfolders = $config['subfolders'] || true
$nonce = $config['nonce']

# No user-serviceable parts below. Also, dragons.
$base_folder = $config['maildir'] || ENV['HOME'] + '/Maildir'

# Everything lives in a UA subfolder. This is Dovecot format.
$base_folder = $base_folder + "/.UA"
$base_api = "http://#{$ua_username}:#{$ua_password}@ua2.org/uaJSON"
$email = 'uatest@ua.frottage.org'
$maildir = Maildir.new($base_folder)
#$maildir.serializer = Maildir::Serializer::Mail.new

p $base_api
p $base_folder
p $nonce
p $subfolders

loop do
    puts "fetching /folders as #{$base_api}/folders"
    r = RestClient.get "#{$base_api}/folders"
    folders_json = r.to_str
    folders = JSON.load(folders_json)

    seen_folders = {}
    mark_read = []
    if folders.size > 0 then
        u_posts = []
        folders.each do |folder_blob|
            folder = folder_blob['folder']
            if folder_blob['unread'] > 0 then
                puts "fetching #{folder}"
                if $subfolders then
                    seen_folders[folder] = Maildir.new($base_folder + ".#{folder.sanitise}")
                else
                    seen_folders[folder] = $maildir
                end
                seen_folders[folder].serializer = Maildir::Serializer::Mail.new

                puts "created #{seen_folders[folder].path}"
                r = RestClient.get("#{$base_api}/folder/#{folder}/unread/full")
                posts_json = r.to_str
                mark_read = []
                folder_posts = JSON.load(posts_json)
                puts "fetched #{folder}, pushed #{folder_posts.size} posts"
                u_posts.push folder_posts
            end
        end

        u_posts.flatten.sort_by {|a| a['id']}.each do |post|
            a = post['inReplyTo']
            reply = case
            when a.nil? then nil
            when a.class == Fixnum then a
            when a.class == Array then a[0]
            else raise 'unknown type of ReplyTo'
            end

            message = new_message(post['subject'], post['from'], post['to'], post['body'], post['id'], post['folder'], post['epoch'], reply)

            # create our RFC2822 email from the UA parts
            reply_to = message.reply_to($ua_username, $nonce)
            email = Mail.new do
                from        message.from.to_email
                to          'list@ua.frottage.org'
                cc          $email
                subject     "[#{message.folder}] #{message.subject}"
                body        message.body
                message_id  "<post-#{message.pid}@ua.frottage.org>"
                date        Time.at(message.epoch)
                reply_to    "reply-#{reply_to} <reply-#{reply_to}@ua.frottage.org>"
            end
            if message.to then
                email.to = message.to.to_email
            end
            if message.parent then
                email['References'] = "<post-#{message.parent}@ua.frottage.org>"
                email['In-Reply-To'] = "<post-#{message.parent}@ua.frottage.org>"
            end
            if $subfolders then
                email.subject = message.subject
            end
            email['Thread-Topic'] = message.subject
            email['List-Id'] = "ua.frottage.org"

            puts email.to_s

            m = seen_folders[message.folder].add(email)
            m.utime(message.epoch, message.epoch)

            # mark_read.push(post['id'])
        end

#      while mark_read.size > 0 do
#          to_send = mark_read.slice!(0,100)
#          r = RestClient.post "#{$base_api}/message/read", to_send.to_json, :content_type => :json, :accept => :json
#          puts "Response #{r.to_str}"
#      end

    end

    exit

    puts "SLEEPING FOR 180s"
    sleep 180
end
