class CamaleonCms::UniqValidatorUser < ActiveModel::Validator
  def validate(record)
    record.errors[:base] << "#{I18n.t('camaleon_cms.admin.users.message.requires_different_username')}" if CamaleonCms::User.where(username: record.username).where.not(id: record.id).where("#{CamaleonCms::User.table_name}.site_id" => record.site_id).size > 0
    record.errors[:base] << "#{I18n.t('camaleon_cms.admin.users.message.requires_different_email')}" if CamaleonCms::User.where(email: record.email).where.not(id: record.id).where("#{CamaleonCms::User.table_name}.site_id" => record.site_id).size > 0

  end
end

class CamaleonCms::User < ActiveRecord::Base
  include CamaleonCms::Metas
  include CamaleonCms::CustomFieldsRead
  self.table_name = PluginRoutes.static_system_info["cama_users_db_table"] || "#{PluginRoutes.static_system_info["db_prefix"]}users"
  # attr_accessible :username, :role, :email, :parent_id, :last_login_at, :site_id, :password, :password_confirmation, :first_name, :last_name #, :profile_attributes
  # attr_accessible :is_valid_email

  default_scope {order("#{CamaleonCms::User.table_name}.role ASC")}

  validates :username, :presence => true
  validates :email, :presence => true, :format => { :with => /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i } #, :unless => Proc.new { |a| a.auth_social.present? }
  validates_with CamaleonCms::UniqValidatorUser

  has_secure_password #validations: :auth_social.nil?

  before_create { generate_token(:auth_token) }
  before_save :before_saved
  before_create :before_saved
  after_create :set_all_sites
  before_destroy :reassign_posts
  # relations

  has_many :metas, ->{ where(object_class: 'User')}, :class_name => "CamaleonCms::Meta", foreign_key: :objectid, dependent: :destroy
  has_many :user_relationships, class_name: "CamaleonCms::UserRelationship", foreign_key: :user_id, dependent: :destroy#,  inverse_of: :user
  has_many :term_taxonomies, foreign_key: :term_taxonomy_id, class_name: "CamaleonCms::TermTaxonomy", through: :user_relationships, :source => :term_taxonomies
  has_many :sites, foreign_key: :term_taxonomy_id, class_name: "CamaleonCms::Site", through: :user_relationships, :source => :term_taxonomies
  has_many :all_posts, class_name: "CamaleonCms::Post"

  #scopes
  scope :admin_scope, -> { where(:role => 'admin') }
  scope :actives, -> { where(:active => 1) }
  scope :not_actives, -> { where(:active => 0) }

  #vars
  STATUS = {0 => 'Active', 1=>'Not Active'}
  ROLE = { 'admin'=>'Administrator', 'client' => 'Client'}

  # return all posts of this user on site
  def posts(site)
    site.posts.where(user_id: self.id)
  end

  def _id
    "#{self.role.upcase}-#{self.id}"
  end

  def fullname
    "#{self.first_name} #{self.last_name}".titleize
  end

  def admin?
    role == 'admin'
  end

  def client?
    self.role == 'client'
  end

  # return the UserRole Object of this user in Site
  def get_role(site)
    @_user_role ||= site.user_roles.where(slug: self.role).first
  end

  def assign_site(site)
    self.user_relationships.where(term_taxonomy_id: site.id).first_or_create
  end

  def roleText
    User::ROLE[self.role]
  end

  def created
    self.created_at.strftime('%d/%m/%Y %H:%M')
  end

  def updated
    self.updated_at.strftime('%d/%m/%Y %H:%M')
  end

  # auth
  def generate_token(column)
    begin
      self[column] = SecureRandom.urlsafe_base64
    end while CamaleonCms::User.exists?(column => self[column])
  end

  def send_password_reset
    generate_token(:password_reset_token)
    self.password_reset_sent_at = Time.zone.now
    save!
  end

  def send_confirm_email
    generate_token(:confirm_email_token)
    self.confirm_email_sent_at = Time.zone.now
    save!
  end

  private
  def create_profile
    self.build_profile if self.profile.nil?
  end

  def before_saved
    self.role = PluginRoutes.system_info["default_user_role"] if self.role.blank?
  end

  def set_all_sites
    CamaleonCms::Site.all.each do |site|
      self.assign_site(site)
    end
  end

  # reassign all posts of this user to first admin
  # reassign all comments of this user to first admin
  # if doesn't exist any other administrator, this will cancel the user destroy
  def reassign_posts
    all_posts.each do |p|
      s = p.post_type.site
      u = s.users.admin_scope.where.not(id: self.id).first
      if u.present?
        p.update_column(:user_id, u.id)
        p.comments.where(user_id: self.id).each do |c|
          c.update_column(:user_id, u.id)
        end
      end
    end
  end

end
