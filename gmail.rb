require 'httpclient'
require 'base64'

class GMail
    def initialize google
        @google = google
        @c = HTTPClient.new
        renew_token
    end

    def renew_token
        @auth_token = @google.get_oauth_token
    end

    def api_call api, method: 'GET', query: nil, body: nil,
                      user_id: 'me'
        tries = 0
        begin
            url = "https://gmail.googleapis.com/gmail/v1/" +
                  "users/#{user_id}/#{api}"
            headers = {
                'Authorization': "Bearer #{@auth_token}",
                'Content-Type': 'application/json',
            }
            r = @c.request method, url, query, body, headers
            if r.code >= 400
                puts "Error #{r.code}: #{r.body}"
                raise '401' if r.code == 401
                return nil
            end
            JSON.parse r.body, symbolize_names: true
        rescue RuntimeError => e
            tries += 1
            if e.message == '401' and tries <= 3
                renew_token
                retry
            end
        end
    end
end
