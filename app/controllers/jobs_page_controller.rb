class JobsPageController < ApplicationController
    def index
      render template: "jobs_page/index"
    end
  end