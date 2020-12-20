# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "date"
require "nokogiri"

LOGINNAME = ENV["loginname"]
PASSWORD = ENV["password"]
USER_ID = ENV["user_id"]

def request_options(uri)
  { use_ssl: uri.scheme == "https" }
end

def fetch_jwt_token
  uri = URI.parse("https://bootcamp.fjord.jp/api/session")
  request = Net::HTTP::Post.new(uri)
  request.content_type = "application/json"
  request.body = JSON.dump({
                             "login_name" => LOGINNAME,
                             "password" => PASSWORD
                           })
  response = http_request(uri, request)
  response.body.gsub(/{\"token\":\"|"}/, "")
end

def http_request(uri, request)
  Net::HTTP.start(uri.hostname, uri.port, request_options(uri)) do |http|
    http.request(request)
  end
end

def fetch_csrf_token
  uri = URI.parse("https://bootcamp.fjord.jp/")
  request = Net::HTTP::Get.new(uri)
  request["Authorization"] = fetch_jwt_token
  response = http_request(uri, request)
  re = Regexp.new("csrf-token.+?==")
  s = response.body
  csrf_token = re.match(s).to_s.gsub('csrf-token" content="', "")
  { csrf_token: csrf_token, cookie: extract_cookie(response) }
end

def extract_cookie(response)
  cookie = {}
  response.get_fields("Set-Cookie").each do |str|
    k, v = str[0...str.index(";")].split("=")
    cookie[k] = v
  end
  cookie
end

def add_cookie(request, cookie)
  request.add_field("Cookie", cookie.map do |k, v|
    "#{k}=#{v}"
  end.join(";"))
  request
end

def create_item(item_node)
  title_anchor = item_node.css(".thread-list-item__title-link")[0]
  username_anchor = item_node.css(".thread-list-item-meta .thread-header__author")[0]
  report_datetime_anchor = item_node.css(".thread-list-item-meta__datetime")[0]

  title = title_anchor.inner_text
  report_url = "https://bootcamp.fjord.jp#{title_anchor.attributes["href"].value}"
  username = username_anchor.inner_text
  report_datetime = report_datetime_anchor.inner_text
  subtitle = "#{username} #{report_datetime}"
  icon = "./icon.png"

  {
    title: title,
    subtitle: subtitle,
    arg: report_url,
    icon: icon
  }
end

def get_reports(token)
  uri = URI.parse("https://bootcamp.fjord.jp/users/#{USER_ID}/reports")
  request = Net::HTTP::Get.new(uri)
  request.content_type = "text/html"
  request = add_cookie(request, token[:cookie])
  response = http_request(uri, request)
  doc = Nokogiri::HTML.parse(response.body, nil, "utf-8")
  thread_list_items =  doc.css(".thread-list-item")
  thread_list_items.map(&method(:create_item))

  {
    items: thread_list_items.map(&method(:create_item))
  }.to_json
end

token = fetch_csrf_token

if (PASSWORD == "password") && (LOGINNAME == "username")
  puts "LOGINNAMEとPASSWORDを設定してください"
  return
end

puts get_reports(token)
