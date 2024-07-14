# frozen_string_literal: true
require 'socket'
require 'openssl'
require 'base64'
require 'cgi'
require 'json'
require 'fileutils'
require 'zlib'
require 'stringio'

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
        if is_source_view
            @is_source_view = true
        else
            if @scheme == "view-source"
                @is_source_view = true
                @scheme, url = url.split(":", 2)
            else
                @is_source_view = false
            end
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
        # general idea is to have a cache folder which contains all the things and then a folder for each webpage
        # in the folder we have the html as well as the headers and all other info in a metadata.json
        
        # there's no real point in caching anything besides actual web requests
        if @scheme == "http" || @scheme == "https"
            # folder_path is the path for the folder, so mkdir can work
            @folder_path = "cache/" + @scheme + "/" + @host
            @file_path = @folder_path + @path
            if @path == "/"
                @file_path << "_"
            end
            
            if File.exist?(@file_path + ".html")
                cache = cache_handling
                return cache if cache
            end
        end
        
        if @scheme == "file"
            # this may or may not work for network files, I have no way of testing it
            File.read(@path)
            
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
                "Keep-Alive": @timeout,
                "User-Agent": "toy_ruby_web_browser",
                "Accept-Encoding": "gzip",
            }
            request = build_request(headers)
            
            # send and recieve
            socket.print(request)
            
            # status information is on first line of response, so nabbbed
            status = socket.readline("\r\n")
            version, status_code, explanation = status.split(" ", 3)
            
            # parse headers
            response_headers = parse_headers(socket)
            
            # redirect handling
            if status_code[0] == "3"
                @redirects -= 1
                raise "Too many redirects" unless @redirects > 0
                puts "redirects left: #{@redirects}"
                
                new_url = response_headers["location"].strip
                new_url_obj = URL.new(new_url, is_source_view, @redirects, @scheme + "://" + host)
                return new_url_obj.request
            end
            
            # finish reading
            if response_headers["transfer-encoding"] == "chunked"
                data = read_chunked_socket_data(socket)
            else
                length = response_headers["content-length"].to_i
                puts response_headers
                data = read_socket_data(socket, length)
            end
            
            if response_headers["content-encoding"] == "gzip"
                puts "gzipped data"
                
                body = Zlib::GzipReader.new(StringIO.new(data.to_s)).read
            else
                body = data
            end
            
            if response_headers["connection"] != "Keep-Alive"
                socket.close
            end
            
            # only caches if allowed and a successful or permanent thing
            if response_headers.key?("cache-control")
                if response_headers["cache-control"] != "no-store" && [200, 301, 404].include?(status_code.to_i)
                    cache_request(response_headers, body)
                end
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
    
    def read_chunked_socket_data(socket)
        puts "reading chunked data"
        data = ""
        line = socket.readline("\r\n")
        next_line = socket.readline("\r\n")
        # take lines 2 at a time, because each chunk has a line for its length
        while line != "0\r\n"
            data += next_line
            line = socket.readline("\r\n")
            next_line = socket.readline("\r\n")
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
    
    def cache_handling
        puts "cached file exists, fetching from #{@file_path}.html"
        cached_req_metadata = JSON.load_file(@file_path + ".json")
        
        if cached_req_metadata.key?("cache-control")
            # checks if cache is within time limit
            if cached_req_metadata["cache-control"].split("=")[1].to_i > (Time.now.to_i - cached_req_metadata["unix"])
                puts "read from cache!"
                cached_req = File.read(@file_path + ".html")
                return cached_req
            else
                puts "cache expired, falling back to new request"
            end
        end
    end
    
    def parse_headers(socket)
        response_headers = {}
        line = socket.readline("\r\n")
        while line != "\r\n"
            header, value = line.split(":", 2)
            
            # check that they both exist, if not raise
            raise "Malformed header: #{header.strip}" unless header && value
            
            response_headers[header.downcase.strip] = value.strip
            line = socket.readline("\r\n")
        end
        
        response_headers
    end
    
    def cache_request(response_headers, body)
        # full file saving business
        response_headers["unix"] = Time.now.to_i
        # makes the folder if it doesn't exist, does nothing otherwise
        FileUtils.mkdir_p(@folder_path)
        File.open(@file_path + ".json", "w+") do |f|
            f.write(JSON.pretty_generate(response_headers))
        end
        File.open(@file_path + ".html", "w+") do |f|
            f.write(body.to_s)
        end
        puts "saved file"
    end
    
    attr_accessor :scheme, :host, :path, :port, :is_source_view
end