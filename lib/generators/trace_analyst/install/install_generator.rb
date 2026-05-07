# frozen_string_literal: true

require 'rails/generators'

module TraceAnalyst
  module Generators
    module Install
      class InstallGenerator < Rails::Generators::Base
        desc 'Install TraceAnalyst Cursor assets, investigation templates, and initializer'

        class_option :subject_key, type: :string, default: 'shop_id'
        class_option :force, type: :boolean, default: false

        def run_installer # :nodoc:
          TraceAnalyst::Installer.new(
            repo_root: destination_root,
            subject_key: options['subject_key'].to_sym,
            branch_prefix: 'trace',
            investigations_dir: 'docs/trace-investigations',
            local_drop_dir: 'tmp/trace-investigations',
            force: options['force']
          ).run
        end
      end
    end
  end
end
