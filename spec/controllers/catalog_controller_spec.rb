require 'spec_helper'

describe CatalogController, :vcr do

  describe "GET 'endnote.endnote'" do

        it "should work for single ids" do 
    #     {"id"=>["323033", "5417238"], "controller"=>"catalog", "action"=>"endnote", "format"=>"endnote", "adv"=>{}}
          get 'endnote', format: 'endnote', params: { id: "100" }
          expect(response).to be_successful
        end

    it "should work for multiple ids" do 
#     {"id"=>["323033", "5417238"], "controller"=>"catalog", "action"=>"endnote", "format"=>"endnote", "adv"=>{}}
      get 'endnote', format: 'endnote', params: { id: ["123", "1234"] }
      expect(response).to be_successful
    end

  end

end

