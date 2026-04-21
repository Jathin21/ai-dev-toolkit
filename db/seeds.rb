# Idempotent seeds. Safe to run multiple times.
#
# Creates a default admin account in development. Does nothing in production
# unless SEED_IN_PRODUCTION=1 is set.

return if Rails.env.production? && ENV["SEED_IN_PRODUCTION"] != "1"

email    = ENV.fetch("SEED_ADMIN_EMAIL", "admin@example.com")
password = ENV.fetch("SEED_ADMIN_PASSWORD", "password1234")

admin = User.find_or_initialize_by(email: email)
admin.assign_attributes(
  name:     "Admin User",
  role:     "admin",
  password: password,
  password_confirmation: password
)
admin.save!

puts "=" * 60
puts "Seeded admin user"
puts "  email:    #{email}"
puts "  password: #{password}"
puts "=" * 60
