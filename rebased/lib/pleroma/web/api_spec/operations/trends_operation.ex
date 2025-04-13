defmodule Pleroma.Web.ApiSpec.TrendsOperation do
  alias OpenApiSpex.Operation
  alias OpenApiSpex.Schema
  alias Pleroma.Web.ApiSpec.Schemas.Tag
  
  def open_api_operation(action) do
    operation = %Operation{
      tags: ["Trends"],
      summary: "Get trending hashtags",
      operationId: "TrendsController.#{action}",
      security: [%{"oAuth" => ["read:trends"]}],
      parameters: [],
      responses: %{
        200 => Operation.response("Array of Tags", "application/json", %Schema{
          type: :array,
          items: Tag
        }),
        404 => Operation.response("Error", "application/json", %Schema{
          type: :object,
          properties: %{
            error: %Schema{type: :string, description: "Error description"}
          }
        })
      }
    }
    
    operation
  end
end