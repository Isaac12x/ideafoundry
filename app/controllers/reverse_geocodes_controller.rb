class ReverseGeocodesController < ApplicationController
  def show
    lat = Float(params[:lat], exception: false)
    lng = Float(params[:lng], exception: false)
    return head :unprocessable_entity unless lat&.between?(-90, 90) && lng&.between?(-180, 180)

    render json: { label: ReverseGeocoder.lookup(lat, lng)&.fetch(:label) }
  end
end
