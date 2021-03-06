module MarketplaceService
  module Person
    PersonModel = ::Person

    module Entity
      Person = EntityUtils.define_entity(
        :id,
        :username,
        :name,
        :full_name,
        :avatar
      )

      module_function

      def person(person_model)
        Person[
          id: person_model.id,
          username: person_model.username,
          name: person_model.name,
          full_name: person_model.full_name,
          avatar: person_model.image.url(:thumb)
        ]
      end
    end

    module Command

      module_function

      def unsubscribe_email_from_community_updates(email_address)
        person = Maybe(Email.find_by_address(email_address)).person.or_else(nil)
        Helper.unsubscribe_from_community_updates(person)
      end

      def unsubscribe_person_from_community_updates(person_id)
        person = PersonModel.find_by_id(person_id)
        Helper.unsubscribe_from_community_updates(person)
      end

      module Helper
        module_function

        def unsubscribe_from_community_updates(person)
          unless person.nil?
            person.min_days_between_community_updates = 100000
            person.save!
          end
        end
      end
    end

    module Query

      module_function

      def person(id)
        MarketplaceService::Person::Entity.person(PersonModel.where({id: id}).first)
      end

      def people(ids)
        PersonModel.where({id: ids}).inject({}) do |memo, person_model|
          memo[person_model.id] = MarketplaceService::Person::Entity.person(person_model)
          memo
        end
      end
    end
  end
end
