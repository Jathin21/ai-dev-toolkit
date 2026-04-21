class User < ApplicationRecord
  devise :database_authenticatable, :registerable, :recoverable,
         :rememberable, :validatable, :trackable

  encrypts :encrypted_github_token, deterministic: false

  ROLES = %w[member admin].freeze

  has_many :repositories,  dependent: :destroy
  has_many :queries,       dependent: :destroy
  has_many :code_searches, dependent: :destroy

  validates :role, inclusion: { in: ROLES }
  validates :name, presence: true

  def admin?
    role == "admin"
  end

  def github_token
    encrypted_github_token.presence || ENV["GITHUB_TOKEN"]
  end
end
