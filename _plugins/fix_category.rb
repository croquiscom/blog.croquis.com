module Jekyll
  class Post
    def populate_categories
      categories_from_data = Utils.pluralized_array_from_hash(data, 'category', 'categories')
      self.categories = categories_from_data.map {|c| c.to_s.downcase}.flatten.uniq
    end
  end
end
