class UsersController < CatalogController

  self.copy_blacklight_config_from(CatalogController)
  before_filter :check_for_logged_in_user, :only => [:my_tapas, :my_projects]
  before_filter :verify_admin, :only => [:index, :show, :edit, :create]

  def my_tapas
    @page_title = "My TAPAS"
    @user = current_user
    self.search_params_logic += [:my_communities_filter]
    (@projects, @document_list) = search_results(params, search_params_logic)
    render 'my_tapas'
  end

  def my_projects
    @page_title = "My Projects"
    @user = current_user
    self.search_params_logic += [:my_communities_filter]
    (@projects, @document_list) = search_results(params, search_params_logic)
    render 'my_projects'
  end

  def index
    @page_title = "Users"
    @users = User.all
  end

  def admin_show
    @user = User.find(params[:id])
    render 'show'
  end

  def edit
    @user = User.find(params[:id])
  end

  def update
    @user = User.find(params[:id])
    @user.name = params[:user][:name]
    @user.email = params[:user][:email]
    @user.role = params[:user][:role]
    @user.save!
    redirect_to @user
  end

  def search_action_url(options = {})
    # Rails 4.2 deprecated url helpers accepting string keys for 'controller' or 'action'
    catalog_index_path(options.except(:controller, :action))
  end

  private
    def my_communities_filter(solr_parameters, user_parameters)
      model_type = RSolr.solr_escape "info:fedora/afmodel:Community"
      query = "has_model_ssim:\"#{model_type}\" && (project_members_ssim:\"#{@user.id}\" OR depositor_tesim:\"#{@user.id}\")"
      solr_parameters[:fq] ||= []
      solr_parameters[:fq] << query
    end

    def check_for_logged_in_user
      if current_user
      else
        render_404("User not signed in") and return
      end
    end

    def verify_admin
      redirect_to root_path unless current_user && current_user.admin?
    end

end
