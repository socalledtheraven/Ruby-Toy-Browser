# frozen_string_literal: true
require_relative "../browser/url.rb"

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
    body = url.request
    show(body, url.is_source_view)
end

def test
    FileUtils.mkdir_p(File.dirname("cache/http/example.org/_.json"))
    File.open("cache/http/example.org/_.json", "w+") do |f|
        f.write("body.to_s")
    end
    
    m = File.read("cache/http/example.org/_.json")
    puts m
end

#

urls = %w[http://example.org/ https://example.org/ file:///C:/Users/tomda/Documents/Code/Ruby/Browser/browser/main.rb data:text/html,Hello%20world! data:text/plain;base64,SGVsbG8sIFdvcmxkIQ== data:text/html,%3Ch1%3EHello%2C%20World%21%3C%2Fh1%3E view-source:https://example.org/ https://browser.engineering/redirect https://browser.engineering/redirect3]
urls.each do |url|
    url_obj = URL.new(url)
    load_url url_obj
end