ActiveAdmin.register TargetGroup do
  include DisableIntercom
  menu parent: 'Targets'

  permit_params :name, :description, :sort_index, :level_id, :milestone, :track_id

  filter :level
  filter :name, as: :string
  filter :description, as: :string
  filter :milestone

  scope :all
  scope('No Track') { |scope| scope.where(track: nil) }

  Track.all.each do |track|
    scope(track.name) { |scope| scope.where track: track }
  end

  controller do
    def scoped_collection
      super.includes :level, :track
    end
  end

  index do
    selectable_column

    column :level
    column :track
    column :milestone
    column :sort_index
    column :name

    actions
  end
end
