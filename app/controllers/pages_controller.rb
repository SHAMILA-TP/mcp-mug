class PagesController < ActionController::Base
  layout "pages"

  def home
    @mugs = Mug.all.order(:size)
    @recent_orders = Order.order(created_at: :desc).limit(5)
  end
end
