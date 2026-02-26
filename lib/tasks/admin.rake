require "io/console"

namespace :admin do
  desc "Create an admin user"
  task create: :environment do
    print "Email address: "
    email_address = $stdin.gets&.strip.to_s

    print "First name (optional): "
    first_name = $stdin.gets&.strip

    print "Last name (optional): "
    last_name = $stdin.gets&.strip

    password = nil
    password_confirmation = nil

    loop do
      print "Password (min 8 chars): "
      password = $stdin.noecho(&:gets)&.strip.to_s
      puts

      print "Confirm password: "
      password_confirmation = $stdin.noecho(&:gets)&.strip.to_s
      puts

      if password.length < 8
        puts "Password must be at least 8 characters."
        next
      end

      if password != password_confirmation
        puts "Passwords do not match."
        next
      end

      break
    end

    admin_user = AdminUser.new(
      email_address:,
      first_name: first_name.presence,
      last_name: last_name.presence,
      password:
    )

    if admin_user.save
      puts "Admin user created: #{admin_user.email_address}"
    else
      puts "Failed to create admin user:"
      admin_user.errors.full_messages.each { |message| puts "- #{message}" }
      exit(1)
    end
  end
end
