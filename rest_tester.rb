#!/usr/bin/env ruby

# rest_tester
# Created by 2017, kyontan <kyontan@monora.me>
# Licenced by CC0 (https://creativecommons.org/publicdomain/zero/1.0/deed.ja) except for module TTy

require "optparse"
require "json"

# module Tty:
#   Copyright (c) 2013, なつき
#   All rights reserved.
#
#   Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
#
#   * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
#   * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
#
#   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
module Tty extend self
  def blue; bold 34; end
  def white; bold 39; end
  def red; color 31; end
  def yellow; color 33 ; end
  def reset; escape 0; end
  def em; underline 39; end
  def green; color 92 end
  def gray; bold 30 end

  private

  def color n
    escape "0;#{n}"
  end

  def bold n
    escape "1;#{n}"
  end

  def underline n
    escape "4;#{n}"
  end

  def escape n
    "\033[#{n}m" if $stdout.tty?
  end
end

def request(host:, path:, method:, params: nil, cookie_file: nil, verbosity: nil, dry_run: false)
  cookie_file = nil if cookie_file == "none"
  print <<-EOS
      #{Tty.blue}  Host:#{Tty.reset} #{host}
      #{Tty.blue}  Path:#{Tty.reset} #{path}
      #{Tty.blue}Params:#{Tty.reset} #{params}
      #{Tty.blue}Cookie:#{Tty.reset} #{cookie_file || "not used"}
  EOS

  format = <<~EOS

        #{Tty.white}Status:#{Tty.reset} %{http_code}
  #{Tty.white}Content-Type:#{Tty.reset} %{content_type}
      #{Tty.white}Redirect:#{Tty.reset} %{redirect_url}
          #{Tty.white}Time:#{Tty.reset} %{time_total}s
  EOS

  cmd = []
  cmd << "curl"
  cmd << "-b #{cookie_file}" if cookie_file
  cmd << "-c #{cookie_file}" if cookie_file
  cmd << "-H 'Accept: application/json'"
  # cmd << "-H 'Origin: #{host}'"
  cmd << "-X #{method}"
  cmd << "-H 'Content-type: application/json'" if params.is_a? String
  cmd << "-d '#{params}'" if params.is_a? String
  cmd << "-d '#{params.map{|k, v| "#{k}=#{v}"}.join(?&)}'" if params.is_a? Hash
  cmd << "-#{?v * verbosity}" if verbosity
  cmd << "-s" if not verbosity
  cmd << "-w '#{format}'"
  cmd << host + path

  puts cmd.join(?\s).gsub(?\n, "\\n") if verbosity || dry_run

  print "    #{Tty.yellow}Response:#{Tty.reset} "
  puts `#{cmd.join(?\s)}` if not dry_run
end

opt = OptionParser.new

method        = "GET"
host          = "http://localhost:3000"
cookie_files  = []
params        = nil
requests_path = nil
verbosity     = nil
dry_run       = false

opt.on("-m method", "--method method") {|m| method = m.upcase }
opt.on("--GET",    %(Shorthand of --method GET"))    { method = "GET" }
opt.on("--POST",   %(Shorthand of --method POST"))   { method = "POST" }
opt.on("--PUT",    %(Shorthand of --method PUT"))    { method = "PUT" }
opt.on("--PATCH",  %(Shorthand of --method PATCH"))  { method = "PATCH" }
opt.on("--DELETE", %(Shorthand of --method DELETE")) { method = "DELETE" }

opt.on("-h host", "--host host", "Default: #{host}") {|h| host = h }

opt.on("-c cookie-file", "--cookie cookie-file") {|f| cookie_files += f.split(/\s*[, ]\s*/) }

opt.on("-j json", "--json json")      {|j| params = j }
opt.on("-r hash", "--ruby ruby-hash") {|h| eval(h).to_json }

opt.on("-v [verbosity]", "--verbosity [verbosity]") {|v| verbosity = v.nil? ? 1 : v.to_i }

opt.on("-d", "--dry-run") {|v| dry_run = true }

# request format: {method: "GET", path: "/hogehoge", params: { login: "hoge", password: "hoge"}, cookie_file: "filepath"}
# request_json: `request format` or Array of `request format`
opt.on("-f request-file", "--file requst-file") {|f| requests_path = f }

opt.parse!(ARGV)

if requests_path
  def request_from_hash(hash, override_host = nil, **opts)
    request(**opts,
           host: override_host || hash["host"],
           path: hash["path"],
         method: hash["method"],
         params: hash["params"],
    )
  end

  requests = JSON.parse(File.read(requests_path))
  requests = [requests] if not requests.is_a? Array


  requests.each do |request_hash|
    raise "Can't understand format of request file." if not request_hash.is_a? Hash

    current_cookie_files = cookie_files.empty? ? [request_hash["cookie_file"]] : cookie_files
    current_cookie_files.each do |cf|
      request_from_hash(request_hash, host, cookie_file: cf, verbosity: verbosity, dry_run: dry_run)
    end
  end

  exit
end

if ARGV.first.start_with? ?/
  path = ARGV.shift
else
  host = ARGV.shift
  path = ARGV.shift

  if not path
    puts opt
    exit
  end
end

escape = '\\\\\\s=' # backslash, spaces, '=' ','
params ||= ARGV.join(" ") \
             .strip \
             .scan(/[^\s]+=(?:\\[#{escape}]|[^#{escape}])+/) \
             .map{|x| x.gsub(/\\([#{escape}])/, '\1') }

opts = { host: host, path: path, method: method, params: params, dry_run: dry_run }

if cookie_files.count.zero?
  request(**opts)
else
  cookie_files.each do |cookie_file|
    request(**opts, cookie_file: cookie_file, verbosity: verbosity)
  end
end
