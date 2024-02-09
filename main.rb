#!/usr/bin/env ruby
require 'colorize'
require 'erb'
require 'json'
require 'nokogiri'
require 'securerandom'
require 'base64'
require 'htmlentities'

require_relative 'oauth'
require_relative 'gmail'
require_relative 'aichat'

CREDENTIALS_FILE = ARGV[0] || 'creds.json'
GO = GoogleOAuth.new CREDENTIALS_FILE
M = GMail.new GO
O = OpenAI::Client.new access_token: '',
                       uri_base: 'http://127.0.0.1:3001',
                       request_timeout: 240
A = AIChat.new O, temperature: 0.0


def get_messages
    time_threshold = (Time.now - 48 * 60 * 60).to_i
    result = M.api_call 'messages', query: {
        q: "in:inbox is:unread after:#{time_threshold}",
    }
    result[:messages] || []
end

def parse_by_mime_type body, mime_type
    val = case mime_type
    when 'text/plain'
        parse_text body
    when 'text/x-amp-html'
        parse_html body
    when 'text/html'
        parse_html body
    else
        raise "Unknown mime type: #{mime_type}"
    end
    val.gsub(/[\u200B-\u200D\uFEFF]+/, '').gsub(/[[:space:]]+/, ' ')
end

def parse_text text
    (text || '').encode('UTF-8', 'binary',
        invalid: :replace, undef: :replace, replace: '.')
end

def parse_html html
    html = Nokogiri::HTML(html)
    html.search('script').remove
    html.search('style').remove
    html.search('image').remove
    HTMLEntities.new.decode html.text.strip
end

def ignore_mime_type? mime_type
    mime_type =~ /image\/.*/ or
    mime_type =~ /application\/.*/ or
        mime_type =~ /audio\/.*/
end

def parse_message_part part, message: nil
    mime_type = part[:mimeType]
    body = if part[:body][:size] > 0 and part[:body][:data]
        Base64.urlsafe_decode64 part[:body][:data]
    else
        nil
    end

    if %w(multipart/alternative multipart/mixed multipart/related).include? mime_type
        text = part[:parts].map do |sub_part|
            parse_message_part sub_part, message: message
        end.join("\n")
        [text, mime_type]
    elsif ignore_mime_type? mime_type
        ['', mime_type]
    else
        [parse_by_mime_type(body, mime_type), mime_type]
    end
end

PROMPT = <<PROMPT
<<PROMPT
Please summarize the following message sent to me (I'm the receiver)
Be very succint!
Do not include any unnecessary data, such as company
numbers. Focus on the underlying message, rather than the
message format. In case of longer message threads, prefer
the newest updates. Remember who the sender is when writing
the summary.

Try to limit your summary to one or two sentences.

Do not include any of the following information in your
summary UNDER ANY CIRCUMSTANCES:
- copyright or trademark
- legal
- "do not reply" in any form. If there is a "do not reply"
  message, ignore it.
- "unsubscribe" in any form. If there is an "unsubscribe"
  message, ignore it.
- that the message is confidential
- that the message is automatically generated

Do not mention the same thing several times.

Today's date: #{Date.today.to_s}
Sender: %{sender}
Recipient: %{recipient}
Subject: %{subject}
Message: %{message_text}
PROMPT

DECISION_PROMPT = <<DECISION_PROMPT
Is this an automated or promotional email that's also not related to work?
Important automated emails (such as from your bank or delivery service)
are not promotional.
Messages forwarded to me by a person are not automated, even if they forward
an automated message.

Answer yes if the message is promotional and not related to work. Answer no otherwise.
Start your answer with 'yes' or 'no'. Do not start with anything else!
DECISION_PROMPT


get_messages[0..].reverse.each do |message|
    message_id = message[:id]
    result = M.api_call "messages/#{message_id}",
        query: { format: 'full' }
    subject = result[:payload][:headers]
        .find{ |x| x[:name] == 'Subject' }[:value]
    sender = result[:payload][:headers]
        .find{ |x| x[:name] == 'From' }[:value]
    recipient = result[:payload][:headers]
        .find{ |x| x[:name] == 'To' }[:value]
    message_text = if result[:payload][:parts]
        result[:payload][:parts].map do |part|
            msg, mime_type = parse_message_part part,
                message: message
            msg
        end.join("\n")
    else
        msg, mime_type =
            parse_message_part result[:payload],
                message: message
        msg
    end

    next unless message_text and message_text.size > 0
    A.reset
    summary = A.chat PROMPT % {
        sender: sender,
        recipient: recipient,
        subject: subject,
        message_text: message_text,
    }
    decision = A.chat DECISION_PROMPT

    if decision =~ /^yes/i or decision =~ /answer is yes/i
        # puts "Skipping message #{subject} (#{sender})".gray
        # puts "Summary: #{summary}".gray
        # puts "Decision: #{decision}".gray
        # puts ''
        next
    end
    print "Message: ".gray
    print subject.yellow
    puts " (#{sender})".gray
    print "Summary: ".gray
    puts summary.green
    # puts "Decision: #{decision}".gray
    puts ''
end

