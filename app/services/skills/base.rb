module Skills
  class Base
    include ActiveModelService

    class << self
      attr_reader :skill_id, :description, :parameters_schema

      def register!(id:, description:, parameters:)
        @skill_id = id.to_s
        @description = description
        @parameters_schema = parameters

        Skills::Registry.register(
          Skills::Registry::Skill.new(
            id: skill_id,
            description: description,
            parameters: parameters,
            callable: method(:execute)
          )
        )
      end

      def execute(params:)
        service = new(params: params)
        service.__send__(:execute)
        {
          result: service.result,
          errors: service.errors.full_messages
        }
      end
    end
  end
end

