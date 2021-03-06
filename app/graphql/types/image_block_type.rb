module Types
  class ImageBlockType < Types::BaseObject
    field :caption, String, null: false
    field :url, String, null: false
    field :filename, String, null: false
  end
end
