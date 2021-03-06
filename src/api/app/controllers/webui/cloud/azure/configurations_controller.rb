module Webui
  module Cloud
    module Azure
      class ConfigurationsController < WebuiController
        before_action :require_login
        before_action :set_azure_configuration

        # PATCH/PUT /cloud/azure/configuration
        def update
          if @azure_configuration.update(permitted_params)
            flash[:success] = 'Successfully updated your Azure configuration.'
          else
            flash[:error] = "Could not update your Azure configuration: #{@azure_configuration.errors.full_messages.to_sentence}."
          end

          redirect_to cloud_azure_configuration_path
        end

        # DELETE /cloud/azure/configuration
        def destroy
          @azure_configuration.destroy!

          flash[:success] = "You've successfully deleted your Azure configuration."
          redirect_to cloud_azure_configuration_path
        end

        private

        def set_azure_configuration
          @azure_configuration = User.session!.azure_configuration || User.session!.create_azure_configuration
        end

        def permitted_params
          params.require(:cloud_azure_configuration).permit(:application_id, :application_key)
        end
      end
    end
  end
end
