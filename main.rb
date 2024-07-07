# frozen_string_literal: true
require './url.rb'

def show(body, view_source=false)
    in_tag = false
    
    body = CGI::unescapeHTML(body)
    
    body.split("").each do |char|
        if view_source
            print char
        else
            # prints only text outside tag brackets
            if char == "<"
                in_tag = true
            elsif char == ">"
                in_tag = false
            elsif not in_tag
                print char
            end
        end
    end
end

def load_url(url)
    url.request
    show(url.body, url.is_source_view)
end

url = "view-source:https://example.org/"
url_obj = URL.new(url)
load_url url_obj