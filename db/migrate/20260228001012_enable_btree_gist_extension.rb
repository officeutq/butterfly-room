class EnableBtreeGistExtension < ActiveRecord::Migration[8.1]
  def change
    enable_extension "btree_gist" unless extension_enabled?("btree_gist")
  end
end
