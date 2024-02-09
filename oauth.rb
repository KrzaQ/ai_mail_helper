require 'json'
require 'signet/oauth_2/client'
require 'httpclient'
require 'securerandom'

class GoogleOAuth
    REDIRECT_URI = 'urn:ietf:wg:oauth:2.0:oob'

    def initialize creds_fn = 'creds.json'
        @creds_fn = creds_fn
        x = begin
            JSON.parse(
                File.read(@creds_fn),
                symbolize_names: true
            ).fetch(:installed, {})
        rescue
            print "Client ID: "
            client_id = STDIN.gets.chomp
            print "Client Secret: "
            client_secret = STDIN.gets.chomp
            data = {
                installed: {
                    client_id: client_id,
                    client_secret: client_secret,
                }
            }
            File.write @creds_fn, JSON.pretty_generate(data)
            data[:installed]
        end

        @client_id = x[:client_id] || SecureRandom.uuid
        @client_secret =
            x[:client_secret] || SecureRandom.uuid
        @refresh_token = x[:refresh_token]
    end

    def get_oauth_token
        unless @refresh_token
            get_refresh_token
        end

        client = HTTPClient.new

        url =  'https://www.googleapis.com/oauth2/v3/token'
        params = {
            client_id: @client_id,
            client_secret: @client_secret,
            refresh_token: @refresh_token,
            grant_type: 'refresh_token'
        }

        param_str = params.map{ "#{_1}=#{_2}" }.join('&')

        final_url = "#{url}?#{param_str}"

        r = HTTPClient.post final_url, ''

        ret = JSON.parse(r.body)
        ret['access_token']
    end

    def get_auth_token
        client = Signet::OAuth2::Client.new(
            authorization_uri:
                'https://accounts.google.com/o/oauth2/auth',
            token_credential_uri:
                'https://oauth2.googleapis.com/token',
            client_id: @client_id,
            client_secret: @client_secret,
            scope: [
                'https://www.googleapis.com/auth/gmail.modify'
            ],
            redirect_uri: 'urn:ietf:wg:oauth:2.0:oob',
            access_type: 'offline',
        )

        puts "Go to #{client.authorization_uri} and " +
            "paste the code:"
        auth_code = STDIN.gets
    end

    def get_refresh_token
        auth_code = get_auth_token
        client = Signet::OAuth2::Client.new(
            token_credential_uri:
                'https://www.googleapis.com/oauth2/v3/token',
            code: auth_code,
            client_id: @client_id,
            client_secret: @client_secret,
            redirect_uri: 'urn:ietf:wg:oauth:2.0:oob',
            grant_type: 'authorization_code'
        )
        client.fetch_access_token!
        @refresh_token = client.refresh_token

        data = JSON.parse File.read(@creds_fn)
        data['installed']['refresh_token'] = @refresh_token
        File.write @creds_fn, JSON.pretty_generate(data)
        @refresh_token
    end
end

