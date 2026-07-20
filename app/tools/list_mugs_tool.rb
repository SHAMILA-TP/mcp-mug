class ListMugsTool < MCP::Tool
  description "List all mugs with their price, size and stock"
  input_schema( 
    properties: {},
    required:[]
    )
  
  def self.call(server_context:)
    mugs = Mug.all.map do |mug|
      { size: mug.size,
        price: mug.price_cents,
        stock: mug.stock }
    end
    MCP::Tool::Response.new([ {
      type: "text",
      text: mugs.to_json
    } ])
  end
end
