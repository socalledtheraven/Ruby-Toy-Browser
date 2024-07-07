# frozen_string_literal: true
require 'socket'
require 'openssl'

class URL
    def initialize(url)
        # normalise \
        url = url.tr("\\", "/")
        # rather than a traditional :// split, use just : for data: urls
        @scheme, url = url.split(":", 2)
        # then we remove the hanging //
        url = url[2..-1]
        
        # we cannot handle most protocols
        # the %w thing is making a list of strings
        raise "protocol failure" unless %w[http https file].include? @scheme
        
        if @scheme == "file"
            @host, @path = url.split("/", 2)
        else
            if url.include?("/")
                @host, url = url.split("/", 2)
                
                @path = "/" + url
                puts @path
            else
                # handles the case when there's no path - ie when top-level domain
                @host = url
                @path = "/"
            end
            
            if @scheme == "http"
                @port = 80
            elsif @scheme == "https"
                @port = 443
            end
            
            if @host.include?(":")
                @host, port = @host.split(":", 2)
                @port = port.to_i
            end
        end
    end
    
    
    def request
        if @scheme == "file"
            # this may or may not work for network files, I have no way of testing it
            f = File.open(@path, "r")
            
            @body = f.read
        else
            # create socket with appropriate port
            socket = TCPSocket.open(@host, @port)
            
            # only redefine if I need it for https
            if @scheme == "https"
                ssl_context = OpenSSL::SSL::SSLContext.new
                socket = OpenSSL::SSL::SSLSocket.new(socket, ssl_context)
                socket.connect
            end
            
            # create request with headers
            headers = {
              Host: @host,
              Connection: "close",
              "User-Agent": "toy_ruby_web_browser",
            }
            request = build_request(headers)
            
            # send and recieve
            socket.print(request)
            response = socket.read
            socket.close
            
            # status information is on first line of response, so nabbbed
            status = response.split("\r\n").first
            version, status_code, explanation = status.split(" ", 3)
            
            headers, @body = response.split("\r\n\r\n", 2)
            
            # cut off the first line
            headers = headers.lines[1..-1].join
            
            response_headers = {}
            headers.each_line do |line|
                header, value = line.split(":", 2)
                # check that they both exist
                if header && value
                    response_headers[header.downcase.strip] = value.strip
                else
                    puts "Malformed header: #{header.strip}"
                end
            end
            
            raise "compressed issue" if response_headers.key?("transfer-encoding")
            raise "compressed issue" if response_headers.key?("content-encoding")
        end
    end
    
    def build_request(headers)
        # standard request boilerplate
        request = "GET #{@path} HTTP/1.1\r\n"
        # add each header
        headers.each do |key, value|
            request << "#{key}: #{value}\r\n"
        end
        # implicit return
        request + "\r\n"
    end
    
    attr_accessor :scheme, :host, :path, :port, :version, :body, :headers
end

def show(body)
    in_tag = false
    
    body.split("").each do |char|
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

def load_url(url)
    url.request
    show(url.body)
end

load_url URL.new(ARGV.first)