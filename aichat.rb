#!/usr/bin/env ruby
require 'colorize'
require 'openai'
require 'json'

MODEL = "mistralai/Mistral-7B-Instruct-v0.2"

client = OpenAI::Client.new(
    access_token: "",
    uri_base: "http://127.0.0.1:3001",
    request_timeout: 240,
)

class AIChat
    attr_reader :client
    attr_accessor :temperature
    attr_accessor :messages
    attr_accessor :system_prompt

    def initialize(client, temperature: 0.7)
        @client = client
        @temperature = temperature
        @system_prompt = "The following is a conversation" +
            " with an AI assistant.  The assistant is " +
            "helpful, creative, clever, very friendly, " +
            "and is very laconic in his answers.\n\n"
        self.reset
    end

    def reset
        @messages = []
    end

    def chat prompt, stream: false
        if @messages.empty?
            @messages << {
                role: "user",
                content: system_prompt + prompt
            }
        else
            @messages << {
                role: "user",
                content: prompt
            }
        end

        message = ""
        if stream
            old_stream = stream
            stream = proc do |chunk|
                delta = chunk.dig("choices", 0, "delta")
                if delta and delta["content"]
                    message += delta["content"]
                    old_stream.call delta["content"]
                end
            end
        end

        response = @client.chat( parameters: {
            model: MODEL,
            messages: @messages,
            temperature: @temperature,
            stream: stream,
        })
        message = response.dig("choices", 0, "message", "content").strip unless stream
        @messages << { role: "assistant", content: message }
        return message
    end
end

if __FILE__ == $0
    chat = AIChat.new(client)

    loop do
        print "You: ".gray
        prompt = gets.chomp
        break if prompt == "quit"
        print "\nBot: ".light_green
        stream = proc do |chunk|
            print chunk.green
        end
        # stream = false
        response = chat.chat(prompt, stream: stream)
        puts response unless stream
        puts "\n\n"
    end
end
