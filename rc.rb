#!/usr/bin/env ruby

# rest_tester
# Created by 2017, kyontan <kyontan@monora.me>
# Licenced by CC0 (https://creativecommons.org/publicdomain/zero/1.0/deed.ja) except for module TTy

require "optparse"
require "shellwords"
require "json"

Signal.trap("PIPE", "EXIT")

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

  def leftpad str, len, color = nil
    (?\s * (len - str.length)) + (color || "") + str + (color && reset || "")
  end

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
    "\033[#{n}m" # if $stdout.tty?
  end
end

def request(host:, path:, method:, params: nil, **opts)
  opts[:cookie_file] = nil if opts[:cookie_file] == "none"

  pad_width, color = 13, Tty.blue

  print <<~EOS if not opts[:only_output]
  #{Tty.leftpad("Host:", pad_width, color)} #{host}
  #{Tty.leftpad("Path:", pad_width, color)} #{path}
  #{Tty.leftpad("Params:", pad_width, color)} #{params}
  #{Tty.leftpad("Cookie:", pad_width, color)} #{opts[:cookie_file] || "not used"}
  EOS

  stat_opts = {
          "Status" => :http_code,
    "Content-Type" => :content_type,
        "Redirect" => :redirect_url,
            "Time" => :time_total,
  }

  format_splitter = ?|
  format = "\n#{stat_opts.values.map{|s| "%{#{s}}" }.join(format_splitter)}"

  cmd = []
  cmd << "curl"
  cmd << "-b #{opts[:cookie_file]}" if opts[:cookie_file]
  cmd << "-c #{opts[:cookie_file]}" if opts[:cookie_file]
  cmd << "-H 'Accept: application/json'"
  # cmd << "-H 'Origin: #{host}'"
  cmd << "-X #{method}"
  cmd << "-H 'Content-type: application/json'" if params.is_a? String
  cmd << "-d '#{params}'" if params.is_a? String
  cmd << "-d '#{params.map{|k, v| "#{k}=#{v}"}.join(?&)}'" if params.is_a? Hash
  cmd << "-#{?v * opts[:verbosity]}" if opts[:verbosity]
  cmd << "-s" if not opts[:verbosity]
  cmd << "-w '#{format}'"
  cmd << host + path

  puts cmd.join(?\s).gsub(?\n, "\\n") if opts[:verbosity] || opts[:dry_run]

  return if opts[:dry_run]


  *output_lines, stat_values = `#{cmd.join(?\s)}`.lines

  if not (code = $?.exitstatus).zero?
    STDERR.puts "#{Tty.leftpad("Error:", 11, Tty.red)} Process failed with exit status #{code}"
    return
  end

  stats = Hash[stat_opts.keys.zip(stat_values.split(format_splitter))]

  # output_leftpad = opts[:only_output] ? 0 : 6
  output_leftpad = 0

  output_lines = JSON.pretty_generate(JSON.parse(output_lines.join)).lines if stats["Content-Type"] == "application/json"

  puts "#{Tty.leftpad("Response:", 13, Tty.yellow)} " if not opts[:only_output]

  output_lines = `echo #{output_lines.join.shellescape} | #{opts[:pipe_cmd]}`.lines if opts[:pipe_cmd]

  output_lines.each{|line| puts ?\s * output_leftpad + line }

  stats.map do |(k, v)|
    print "#{Tty.leftpad(k + ?:, 13, Tty.white)} "
    puts case k
      when "Status"
        case v.to_i
        when 200..299 then Tty.green
        when 300..399 then Tty.yellow
        when 400..499 then Tty.blue
        when 500..599 then Tty.red
        else Tty.reset
        end + v + Tty.reset
      when "Time" then "#{v}s"
      else v
      end
  end if not opts[:only_output]
end

def print_split_line(len = 40)
  puts ?- * [len, `tput cols`.to_i].min
end

opt = OptionParser.new

method        = "GET"
host          = "http://localhost:3000"
cookie_files  = []
params        = nil
requests_path = nil
other_opts    = { verbosity: nil, dry_run: false, only_output: false, pipe_cmd: nil }

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

opt.on("-v [verbosity]", "--verbosity [verbosity]") {|v| other_opts[:verbosity] = v.nil? ? 1 : v.to_i }

opt.on("-d", "--dry-run") {|v| other_opts[:dry_run] = true }
opt.on("-o", "--only-output") {|v| other_opts[:only_output] = true }

# request format: {method: "GET", path: "/hogehoge", params: { login: "hoge", password: "hoge"}, cookie_file: "filepath"}
# request_json: `request format` or Array of `request format`
opt.on("-f request-file", "--file requst-file") {|f| requests_path = f }

opt.parse!(ARGV)

if requests_path
elsif ARGV.first&.start_with? ?/
  path = ARGV.shift
else
  host = ARGV.shift
  path = ARGV.shift

  if not path
    puts opt
    exit
  end
end

other_opts[:pipe_cmd] = ARGV.map(&:shellescape).join(?\s) if not ARGV.empty?

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
    current_cookie_files.each.with_index do |cf, i|
      print_split_line if not i.zero?
      request_from_hash(request_hash, host, cookie_file: cf, **other_opts)
    end
  end

  exit
end

escape = '\\\\\\s=' # backslash, spaces, '=' ','
params ||= ARGV.join(" ") \
             .strip \
             .scan(/[^\s]+=(?:\\[#{escape}]|[^#{escape}])+/) \
             .map{|x| x.gsub(/\\([#{escape}])/, '\1') }

opts = { host: host, path: path, method: method, params: params, **other_opts }

if cookie_files.count.zero?
  request(**opts)
else
  Dir[*cookie_files].flatten.each.with_index do |cookie_file, i|
    print_split_line if not i.zero?
    request(**opts, cookie_file: cookie_file, **other_opts)
  end
end
