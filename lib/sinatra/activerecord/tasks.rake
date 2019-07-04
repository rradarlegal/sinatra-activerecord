require "active_support/core_ext/string/strip"
require "pathname"
require "fileutils"

db_namespace = namespace :db do
  desc "Create a migration (parameters: NAME, VERSION)"
  task :create_migration do
    unless ENV["NAME"]
      puts "No NAME specified. Example usage: `rake db:create_migration NAME=create_users`"
      exit
    end

    name    = ENV["NAME"]
    version = ENV["VERSION"] || Time.now.utc.strftime("%Y%m%d%H%M%S")

    ActiveRecord::Migrator.migrations_paths.each do |directory|
      next unless File.exist?(directory)
      migration_files = Pathname(directory).children
      if duplicate = migration_files.find { |path| path.basename.to_s.include?(name) }
        puts "Another migration is already named \"#{name}\": #{duplicate}."
        exit
      end
    end

    filename = "#{version}_#{name}.rb"
    dirname  = ActiveRecord::Migrator.migrations_paths.first
    path     = File.join(dirname, filename)
    ar_maj   = ActiveRecord::VERSION::MAJOR
    ar_min   = ActiveRecord::VERSION::MINOR
    base     = "ActiveRecord::Migration"
    base    += "[#{ar_maj}.#{ar_min}]" if ar_maj >= 5

    FileUtils.mkdir_p(dirname)
    File.write path, <<-MIGRATION.strip_heredoc
      class #{name.camelize} < #{base}
        def change
        end
      end
    MIGRATION

    puts path
  end

  desc "Rolls the schema back to the previous version (specify steps w/ STEP=n)."
  task rollback: :load_config do
    ActiveRecord::Base.configurations.configs_for(env_name: SERVER_ENV).each do |db_config|
      step = ENV["STEP"] ? ENV["STEP"].to_i : 1
      ActiveRecord::Base.establish_connection(db_config.config)
      ActiveRecord::Base.connection.migration_context.rollback(step)
    end
    db_namespace["_dump"].invoke
  end

  namespace :rollback do
    ActiveRecord::Base.configurations.configs_for(env_name: SERVER_ENV).each do |spec|
      spec_name = spec.spec_name
      desc "Rolls the schema of #{spec_name} database back to the previous version (specify steps w/ STEP=n)."
      task spec_name => :load_config do
        db_config = ActiveRecord::Base.configurations.configs_for(env_name: SERVER_ENV, spec_name: spec_name)
        step = ENV["STEP"] ? ENV["STEP"].to_i : 1
        ActiveRecord::Base.establish_connection(db_config.config)
        ActiveRecord::Base.connection.migration_context.rollback(step)
        db_namespace["_dump"].invoke
      end
    end
  end
end

# The `db:create` and `db:drop` command won't work with a DATABASE_URL because
# the `db:load_config` command tries to connect to the DATABASE_URL, which either
# doesn't exist or isn't able to drop the database. Ignore loading the configs for
# these tasks if a `DATABASE_URL` is present.
if ENV.has_key? "DATABASE_URL"
  Rake::Task["db:create"].prerequisites.delete("load_config")
  Rake::Task["db:drop"].prerequisites.delete("load_config")
end
