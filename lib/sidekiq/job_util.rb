require "securerandom"
require "time"

module Sidekiq
  module JobUtil
    # These functions encapsulate various job utilities.
    # They must be simple and free from side effects.

    def validate(item)
      raise(ArgumentError, "Job must be a Hash with 'class' and 'args' keys: `#{item}`") unless item.is_a?(Hash) && item.key?("class") && item.key?("args")
      raise(ArgumentError, "Job args must be an Array: `#{item}`") unless item["args"].is_a?(Array)
      raise(ArgumentError, "Job class must be either a Class or String representation of the class name: `#{item}`") unless item["class"].is_a?(Class) || item["class"].is_a?(String)
      raise(ArgumentError, "Job 'at' must be a Numeric timestamp: `#{item}`") if item.key?("at") && !item["at"].is_a?(Numeric)
      raise(ArgumentError, "Job tags must be an Array: `#{item}`") if item["tags"] && !item["tags"].is_a?(Array)

      if Sidekiq.options[:raise_on_complex_arguments] && !json_safe?(item)
        msg = <<~EOM
          Arguments must be native JSON types, see https://github.com/mperham/sidekiq/wiki/Best-Practices.

          To disable this error, remove `Sidekiq.strict_mode!` from your initializer.
        EOM
        raise(ArgumentError, msg)
      elsif !Sidekiq.options[:disable_complex_argument_warning] && Sidekiq.options[:environment] == "development" && !json_safe?(item)
        Sidekiq.logger.warn <<~EOM
          Job arguments do not serialize to JSON safely. This will raise an error in Sidekiq 7.0.

          See https://github.com/mperham/sidekiq/wiki/Best-Practices or raise the error today
          by calling `Sidekiq.strict_mode!` during Sidekiq initialization.
        EOM
      end
    end

    def normalize_item(item)
      validate(item)

      # merge in the default sidekiq_options for the item's class and/or wrapped element
      # this allows ActiveJobs to control sidekiq_options too.
      defaults = normalized_hash(item["class"])
      defaults = defaults.merge(item["wrapped"].get_sidekiq_options) if item["wrapped"].respond_to?("get_sidekiq_options")
      item = defaults.merge(item)

      raise(ArgumentError, "Job must include a valid queue name") if item["queue"].nil? || item["queue"] == ""

      item["class"] = item["class"].to_s
      item["queue"] = item["queue"].to_s
      item["jid"] ||= SecureRandom.hex(12)
      item["created_at"] ||= Time.now.to_f

      item
    end

    def normalized_hash(item_class)
      if item_class.is_a?(Class)
        raise(ArgumentError, "Message must include a Sidekiq::Worker class, not class name: #{item_class.ancestors.inspect}") unless item_class.respond_to?("get_sidekiq_options")
        item_class.get_sidekiq_options
      else
        Sidekiq.default_worker_options
      end
    end

    private

    def json_safe?(item)
      JSON.parse(JSON.dump(item['args'])) == item['args']
    end
  end
end
