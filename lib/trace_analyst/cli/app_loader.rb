# frozen_string_literal: true

module TraceAnalyst
  module CLI
    module AppLoader
      module_function

      def load_rails!(root: Paths.repo_root)
        env_path = File.join(root, 'config', 'environment.rb')
        unless File.file?(env_path)
          raise Error,
                "Could not find Rails app at #{root}. Set TRACE_ANALYST_REPO_ROOT or run from the app directory."
        end

        require env_path
      end
    end
  end
end
