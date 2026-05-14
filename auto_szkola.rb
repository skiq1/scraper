# frozen_string_literal: true
# encoding: UTF-8

require "dotenv/load"
require "net/http"
require "uri"
require "nokogiri"
require "json"
require "digest"

require_relative "services/discord_notifier"
require_relative "services/logger_factory"

URL = ENV.fetch("AUTO_SZKOLA_URL", nil)
STATE_FILE = "known_terms.json"

MONTHS = %w[
  styczeń luty marzec kwiecień maj czerwiec
  lipiec sierpień wrzesień październik listopad grudzień
].freeze

DAYS = %w[
  Poniedziałek Wtorek Środa Czwartek Piątek Sobota Niedziela
].freeze

DISCORD_WEBHOOK_URL = ENV.fetch("DISCORD_WEBHOOK_URL", nil)

logger = Services::LoggerFactory.build(log_path: "auto_szkola.log")

notifier = Services::DiscordNotifier.new(
  webhook_url: ENV.fetch("DISCORD_WEBHOOK_URL"),
  logger: logger
)

def fetch_html(url)
  uri = URI(url)

  request = Net::HTTP::Get.new(uri)
  request["User-Agent"] = "Mozilla/5.0 (X11; Linux x86_64; rv:126.0) Gecko/20100101 Firefox/126.0"
  request["Accept"] = "text/html,application/xhtml+xml"

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
    http.request(request)
  end

  unless response.is_a?(Net::HTTPSuccess)
    raise "HTTP error: #{response.code} #{response.message}"
  end
  response.body
end

def normalize(text)
  text.gsub(/\u00A0/, " ")
      .gsub(/[[:space:]]+/, " ")
      .strip
end

def extract_terms(html)
  doc = Nokogiri::HTML(html)
  text = normalize(doc.text)

  start_index = text.index("Terminy")
  return [] unless start_index

  end_index = text.index("Porównaj", start_index) || text.length
  terms_text = text[start_index...end_index]

  month_pattern = MONTHS.join("|")
  day_pattern = DAYS.join("|")

  # 13 grudzień 2024 Piątek 09:00-15:00 1 miejsc Zapisz się
  regex = /
    (?<date>\d{1,2}\s+(?:#{month_pattern})\s+\d{4})
    \s+
    (?<day>#{day_pattern})
    \s+
    (?<time>\d{2}:\d{2}\s*-\s*\d{2}:\d{2})
    \s+
    (?<places>\d+)\s+miejsc
  /x

  terms_text.scan(regex).map do |date, day, time, places|
    term = {
      "date" => normalize(date),
      "day" => normalize(day),
      "time" => normalize(time),
      "places" => places.to_i
    }

    term["id"] = Digest::SHA256.hexdigest(
      [term["date"], term["day"], term["time"]].join("|")
    )

    term
  end
end

def load_known_terms
  return [] unless File.exist?(STATE_FILE)

  JSON.parse(File.read(STATE_FILE))
rescue JSON::ParserError
  warn "Warning: Could not parse #{STATE_FILE}"
  []
end

def save_known_terms(terms)
  File.write(STATE_FILE, JSON.pretty_generate(terms))
end

def format_term(term)
  "- #{term["date"]}, #{term["day"]}, #{term["time"]}, places: #{term["places"]}"
end

def print_term(term)
  puts format_term(term)
end

begin
  html = fetch_html(URL)
  current_terms = extract_terms(html)

  known_terms = load_known_terms
  known_terms_by_id = known_terms.to_h { |t| [t["id"], t] }

  new_terms = []
  increased_places = []

  current_terms.each do |current|
    known_term = known_terms_by_id[current["id"]]

    if known_terms_by_id[current["id"]].nil?
      new_terms << current
    elsif known_term["places"].to_i < current["places"].to_i
      increased_places << {
        "term" => current,
        "old_places" => known_term["places"].to_i,
        "new_places" => current["places"].to_i
      }
    end
  end

  if new_terms.empty? && increased_places.empty?
    # puts "No changes. [#{Time.now}]"
    logger.info("No changes.")
    return
  end

  if new_terms.any?
    message =
      "New terms:\n" +
      new_terms.map { |term| format_term(term) }.join("\n")

    logger.info(message)
    notifier.notify(message)
  end

  if increased_places.any?
    message =
      "Increased places:\n" +
      increased_places.map do |change|
        term = change["term"]

        "#{format_term(term)}: #{change["old_places"]} -> #{change["new_places"]} places"
      end.join("\n")

    logger.info(message)
    notifier.notify(message)
  end

  all_terms_by_id = (current_terms + known_terms).uniq { |term| term["id"] }
  save_known_terms(all_terms_by_id)
rescue StandardError => e
  logger.error("Error: #{e.message}")
  warn "[#{Time.now}] Error: #{e.message}"
  exit 1
end
