class CreateOrderTool < MCP::Tool
  description "Order a mug in a given size and quantity"
  input_schema(
    properties: {
      size:{
        type: "string",
        enum: ["S", "M", "L"]
      },
      quantity: { type: "integer" }
    },
    required: ["size", "quantity"]
  )
  def self.call( size:, quantity:, server_context: )
    mug = Mug.find_by(size: size)
    if mug.nil?
      return MCP::Tool::Response.new([{ type: "text", text: "No mug found for size #{size}" }])
    end

    if mug.stock < quantity
      return MCP::Tool::Response.new([{ type: "text", text: "Not enough stock for size #{size}. Available: #{mug.stock}" }])
    end

    order = nil
    ActiveRecord::Base.transaction do
      order = Order.create!(mug: mug, quantity: quantity, customer_identifier: server_context[:user_id])
      mug.update!(stock: mug.stock - quantity)
    end
    MCP::Tool::Response.new([{
      type: "text",
      text: "Order ##{order.id} placed: #{quantity} x #{size} mug(s)."
    }]

    )
  end
end