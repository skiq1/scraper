# frozen_string_literal: true
# encoding: UTF-8

require "logger"
require "fileutils"
require "pathname"

module Services
  class LoggerFactory
    DEFAULT_LOG_DIR = "logs"

    def self.build(log_path:)
      resolved_log_path = resolve_log_path(log_path)

      FileUtils.mkdir_p(File.dirname(resolved_log_path))

      logger = Logger.new(resolved_log_path, "daily")
      logger.level = Logger::INFO
      logger.datetime_format = "%Y-%m-%d %H:%M:%S"

      logger.formatter = proc do |severity, datetime, _progname, message|
        "[#{datetime}] #{severity}: #{message}\n"
      end

      logger
    end

    def self.resolve_log_path(log_path)
      path = Pathname.new(log_path)

      if path.dirname.to_s == "."
        File.join(DEFAULT_LOG_DIR, log_path)
      else
        log_path
      end
    end

    private_class_method :resolve_log_path
  end
end
