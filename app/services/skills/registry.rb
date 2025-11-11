module Skills
  class Registry
    Skill = Struct.new(:id, :description, :parameters, :callable, keyword_init: true)

    class << self
      def register(skill)
        skills[skill.id.to_s] = skill
      end

      def fetch(id)
        skills[id.to_s]
      end

      def all
        skills.values
      end

      def clear!
        skills.clear
      end

      private

      def skills
        @skills ||= {}
      end
    end
  end
end

