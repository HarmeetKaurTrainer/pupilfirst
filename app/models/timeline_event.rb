# encoding: utf-8
# frozen_string_literal: true

class TimelineEvent < ActiveRecord::Base
  belongs_to :startup
  belongs_to :user
  belongs_to :timeline_event_type
  belongs_to :target

  has_one :karma_point, as: :source
  has_many :timeline_event_files, as: :files

  mount_uploader :image, TimelineImageUploader
  serialize :links
  validates_presence_of :event_on, :startup_id, :user_id, :timeline_event_type, :description
  delegate :private?, to: :timeline_event_type

  MAX_DESCRIPTION_CHARACTERS = 300

  VERIFIED_STATUS_PENDING = -'Pending'
  VERIFIED_STATUS_NEEDS_IMPROVEMENT = -'Needs Improvement'
  VERIFIED_STATUS_VERIFIED = -'Verified'

  def self.valid_verified_status
    [VERIFIED_STATUS_VERIFIED, VERIFIED_STATUS_PENDING, VERIFIED_STATUS_NEEDS_IMPROVEMENT]
  end

  validates_inclusion_of :verified_status, in: valid_verified_status

  GRADE_GOOD = -'good'
  GRADE_GREAT = -'great'
  GRADE_WOW = -'wow'

  def self.valid_grades
    [GRADE_GOOD, GRADE_GREAT, GRADE_WOW]
  end

  normalize_attribute :grade
  validates_inclusion_of :grade, in: valid_grades, allow_nil: true

  before_validation do
    # default verified_status to pending unless verified_at is present
    if verified_at.present?
      self.verified_status = VERIFIED_STATUS_VERIFIED
    else
      self.verified_status ||= VERIFIED_STATUS_PENDING
    end
  end

  validates_length_of :description,
    maximum: MAX_DESCRIPTION_CHARACTERS,
    message: "must be within #{MAX_DESCRIPTION_CHARACTERS} characters"

  scope :end_of_iteration_events, -> { where(timeline_event_type: TimelineEventType.end_iteration) }
  scope :batched, -> { joins(:startup).merge(Startup.batched) }
  scope :verified, -> { where(verified_status: VERIFIED_STATUS_VERIFIED) }
  scope :pending, -> { where(verified_status: VERIFIED_STATUS_PENDING) }
  scope :needs_improvement, -> { where(verified_status: VERIFIED_STATUS_NEEDS_IMPROVEMENT) }
  scope :has_image, -> { where.not(image: nil) }
  scope :from_approved_startups, -> { joins(:startup).where(startups: { approval_status: Startup::APPROVAL_STATUS_APPROVED }) }
  scope :showcase, -> { includes(:timeline_event_type, :startup).verified.from_approved_startups.batched.has_image.order('timeline_events.event_on DESC') }
  scope :help_wanted, -> { where(timeline_event_type: TimelineEventType.help_wanted) }
  scope :for_batch, -> (batch) { joins(:startup).where(startups: { batch_id: batch }) }

  after_initialize :make_links_an_array

  def make_links_an_array
    self.links ||= []
  end

  before_save :ensure_links_is_an_array

  def ensure_links_is_an_array
    self.links = [] if links.nil?
  end

  before_validation :build_description

  def build_description
    return unless !description.present? && auto_populated
    self.description = case timeline_event_type.key
      when 'registered_on_sv'
        'We just registered our startup on SV.CO. Looking forward to an amazing learning experience!'
    end
  end

  after_commit do
    startup.update_stage! if timeline_event_type.stage_change?
  end

  attr_accessor :auto_populated

  def iteration
    startup.iteration(at_event: self)
  end

  def end_iteration?
    timeline_event_type.end_iteration?
  end

  def update_and_require_reverification(params)
    params[:verified_at] = nil
    params[:verified_status] = VERIFIED_STATUS_PENDING
    update(params)
  end

  def verify!
    update!(verified_status: VERIFIED_STATUS_VERIFIED, verified_at: Time.now)

    add_link_for_new_deck!
    add_link_for_new_wireframe!
    add_link_for_new_prototype!
    add_link_for_new_video!
    add_link_for_new_resume!
  end

  def unverify!
    update!(verified_status: VERIFIED_STATUS_PENDING, verified_at: nil)
  end

  def mark_needs_improvement!
    update!(verified_status: VERIFIED_STATUS_NEEDS_IMPROVEMENT, verified_at: nil)
  end

  def verified?
    self.verified_status == VERIFIED_STATUS_VERIFIED
  end

  def pending?
    self.verified_status == VERIFIED_STATUS_PENDING
  end

  def needs_improvement?
    self.verified_status == VERIFIED_STATUS_NEEDS_IMPROVEMENT
  end

  def month_old?
    created_at < 1.month.ago
  end

  def public_link?
    links.select { |l| !l[:private] }.present?
  end

  def points_for_grade
    {
      GRADE_GOOD => 10,
      GRADE_GREAT => 20,
      GRADE_WOW => 40
    }.with_indifferent_access[grade]
  end

  # A hidden timeline event is not displayed to user if user isn't logged in, or isn't the user linked to event.
  def hidden_from?(viewer)
    return false unless timeline_event_type.private?
    return true unless viewer.present?
    user != viewer
  end

  private

  def add_link_for_new_resume!
    return unless timeline_event_type.resume_submission? && links[0].try(:[], :url).present?
    user.update!(resume_url: links[0][:url])
  end

  def add_link_for_new_deck!
    return unless timeline_event_type.new_deck? && links[0].try(:[], :url).present?
    return if links[0].try(:[], :private)
    startup.update!(presentation_link: links[0][:url])
  end

  def add_link_for_new_wireframe!
    return unless timeline_event_type.new_wireframe? && links[0].try(:[], :url).present?
    return if links[0].try(:[], :private)
    startup.update!(wireframe_link: links[0][:url])
  end

  def add_link_for_new_prototype!
    return unless timeline_event_type.new_prototype? && links[0].try(:[], :url).present?
    return if links[0].try(:[], :private)
    startup.update!(prototype_link: links[0][:url])
  end

  def add_link_for_new_video!
    return unless timeline_event_type.new_video? && links[0].try(:[], :url).present?
    return if links[0].try(:[], :private)
    startup.update!(product_video: links[0][:url])
  end
end
