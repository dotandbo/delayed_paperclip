require 'rubygems'

begin
  require 'test/unit'
rescue
  # we are probably Rails 4.2, so no Test::Unit here
  # move along...
  puts "No Test::Unit available. Skipping..."
  exit(0)
end

require 'mocha/setup'
require 'active_record'
require 'active_record/version'
require 'active_support'
require 'active_support/core_ext'
require 'logger'
require 'sqlite3'

begin
  require 'pry'
rescue LoadError
  # Pry is not available, just ignore.
end

require 'paperclip/railtie'
Paperclip::Railtie.insert

ROOT       = File.join(File.dirname(__FILE__), '..')
RAILS_ROOT = ROOT
$LOAD_PATH << File.join(ROOT, 'lib')

require 'delayed_paperclip/railtie'
DelayedPaperclip::Railtie.insert

class Test::Unit::TestCase
  def setup
    silence_warnings do
      Object.const_set(:Rails, stub('Rails', :root => ROOT, :env => 'test'))
    end
  end
end

FIXTURES_DIR = File.join(File.dirname(__FILE__), "fixtures")
config = YAML::load(IO.read(File.dirname(__FILE__) + '/database.yml'))
ActiveRecord::Base.logger = Logger.new(File.dirname(__FILE__) + "/debug.log")
ActiveRecord::Base.establish_connection(config['test'])
Paperclip.logger = ActiveRecord::Base.logger


# Reset table and class with image_processing column or not
def reset_dummy(options = {})
  options[:with_processed] = true unless options.key?(:with_processed)
  build_dummy_table(options[:with_processed])
  reset_class("Dummy", options)
end

# Dummy Table for images
# with or without image_processing column
def build_dummy_table(with_processed)
  ActiveRecord::Base.connection.create_table :dummies, :force => true do |t|
    t.string   :name
    t.string   :image_file_name
    t.string   :image_content_type
    t.integer  :image_file_size
    t.datetime :image_updated_at
    t.boolean(:image_processing, :default => false) if with_processed
  end
end


def reset_class(class_name, options)
  # setup class and include paperclip
  options[:paperclip] = {} if options[:paperclip].nil?
  ActiveRecord::Base.send(:include, Paperclip::Glue)
  Object.send(:remove_const, class_name) rescue nil

  # Set class as a constant
  klass = Object.const_set(class_name, Class.new(ActiveRecord::Base))

  # Setup class with paperclip and delayed paperclip
  klass.class_eval do
    include Paperclip::Glue

    has_attached_file :image, options[:paperclip]
    options.delete(:paperclip)

    validates_attachment :image, :content_type => { :content_type => "image/png" }

    process_in_background :image, options if options[:with_processed]

    after_update :reprocess if options[:with_after_update_callback]

    def reprocess
      image.reprocess!
    end

  end

  klass.reset_column_information
  klass
end
