class EnablePgvectorExtension < ActiveRecord::Migration[7.1]
  def up
    enable_extension "vector"
    enable_extension "pgcrypto"
  end

  def down
    disable_extension "vector"
    disable_extension "pgcrypto"
  end
end
