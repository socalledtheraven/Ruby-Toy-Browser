# frozen_string_literal: true
require 'socket'
require 'openssl'
require 'base64'
require 'cgi'

class URL
    @timeout = 20
    
    def initialize(url, is_source_view = false, redirects = 5, old_url = "")
        @redirects = redirects
        
        # handle the weirdness of redirects sometimes doing
        if redirects < 5 && url[0] == "/"
            url = old_url + url
        end
        puts "creating URL #{url}"
        
        # normalise \
        url = url.tr("\\", "/")
        
        # rather than a traditional :// split, use just : for data: urls
        @scheme, url = url.split(":", 2)
        
        # handles when source view (can be handled recursively)
        if @scheme == "view-source"
            @is_source_view = true
            @scheme, url = url.split(":", 2)
        else
            @is_source_view = false
        end
        
        # the other part of the data: urls
        unless @scheme == "data"
            # then we remove the hanging //
            url = url[2..-1]
        end
        
        # we cannot handle most protocols
        # the %w thing is making a list of strings
        raise "protocol failure" unless %w[http https file data view-source].include? @scheme
        
        
        if @scheme == "file"
            @host, @path = url.split("/", 2)
        elsif @scheme == "data"
            @host = "localhost"
            @port = 8000
            @type, @content = url.split(",", 2)
            
            # sometimes doesn't include typing
            if @type.include? "/"
                @type, @subtype = @type.split("/", 2)
                
                if @subtype.include? ";"
                    @subtype, @format = @subtype.split(";", 2)
                end
            end
            
        elsif @scheme == "http" || @scheme == "https"
            if url.include?("/")
                @host, url = url.split("/", 2)
                
                @path = "/" + url
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
            
            body = f.read
            f.close
            
            body
        elsif @scheme == "data"
            # we cannot currently support anything more complicated
            if @type == "text" || @type == ""
                # not sure about any other formats
                if @format == "base64"
                    @content = Base64.decode64(@content)
                end
                
                # control for %20 etc
                CGI::unescape(@content)
            end
        elsif @scheme == "http" || @scheme == "https"
            # create socket with appropriate port
            socket = create_socket
            
            # create request with headers
            headers = {
                Host: @host,
                Connection: "keep-alive",
                "Keep-Alive": @Timeout,
                "User-Agent": "toy_ruby_web_browser",
            }
            request = build_request(headers)
            
            # send and recieve
            socket.print(request)
            
            # status information is on first line of response, so nabbbed
            status = socket.readline("\r\n")
            version, status_code, explanation = status.split(" ", 3)
            
            response_headers = {}
            line = socket.readline("\r\n")
            while line != "\r\n"
                header, value = line.split(":", 2)
                
                # check that they both exist, if not raise
                raise "Malformed header: #{header.strip}" unless header && value
                
                response_headers[header.downcase.strip] = value.strip
                line = socket.readline("\r\n")
            end
            
            if status_code[0] == "3" && @redirects > 0
                @redirects -= 1
                puts "redirects left: #{@redirects}"
                new_url = response_headers["location"].strip
                
                new_url_obj = URL.new(new_url, @is_source_view, @redirects, @scheme + "://" + host)
                
                return new_url_obj.request
            end
            
            raise "compressed issue" if response_headers.key?("transfer-encoding")
            raise "compressed issue" if response_headers.key?("content-encoding")
            
            length = response_headers["content-length"].to_i
            
            body = read_socket_data(socket, length)
            
            if response_headers["connection"] != "Keep-Alive"
                socket.close
            end
            
            body
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
    
    def read_socket_data(socket, length)
        data = ""
        bytes_read = 0
        
        while bytes_read < length
            chunk = socket.read(length - bytes_read)
            if chunk == "\r\n"
                break
            end
            data += chunk
            bytes_read += chunk.length
        end
        
        data
    end
    
    def create_socket
        socket = TCPSocket.open(@host, @port)
        
        # only redefine if I need it for https
        if @scheme == "https"
            ssl_context = OpenSSL::SSL::SSLContext.new
            socket = OpenSSL::SSL::SSLSocket.new(socket, ssl_context)
            socket.connect
        end
        
        socket
    end
    
    attr_accessor :scheme, :host, :path, :port, :is_source_view
end