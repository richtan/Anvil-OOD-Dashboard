class CustomCache
  def self.fetch(key, options = {})
    value = Rails.cache.read(key)
    return value if value

    value = yield
    Rails.cache.write(key, value, options)
    value
  end
end
