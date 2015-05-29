require "zip"

class CoreFileUpserter
  include Concerns::Upserter

  def upsert 
    begin 
      if Did.exists_by_did?(params[:did])
        core_file = CoreFile.find_by_did(params[:did])
      else
        core_file = CoreFile.new(:did => params[:did])
      end

      update_core_file_metadata!(core_file)
      update_core_file_tei_file!(core_file) if params[:file]
      update_support_files!(core_file) if params[:support_files].present?
    rescue => e 
      ExceptionNotifier.notify_exception(e, :data => { :params => params })
      raise e 
    ensure
      FileUtils.rm(params[:file][:path]) if params[:file][:path]
    end
  end


  def update_core_file_metadata!(core_file)
    did = core_file.did
    core_file.depositor = params[:depositor] if params[:depositor].present?
    core_file.drupal_access = params[:access] if params[:access].present?
    core_file.og_reference = params[:collection_did] if params[:collection_did].present?

    # Make sure to rewrite the did/pid after updating MODS.
    core_file.mods.content = params[:mods] if params[:mods].present?
    core_file.did = did 
    core_file.mods.identifier = core_file.pid

    if params[:collection_did].present?
      core_file.save! unless core_file.persisted?

      if Did.exists_by_did? params[:collection_did]
        core_file.collection = Collection.find_by_did params[:collection_did]
      else
        core_file.collection = Collection.phantom_collection
      end
    end

    # Rewrite the ography relationship that this core file has
    # Currently, every core file can only be one kind of ography
    if params[:file_type].present?
      case params[:file_type]
      when "otherography"
        clear_and_update_ography!(core_file, :otherography_for=) 
      when "personography"
        clear_and_update_ography!(core_file, :personography_for=)
      when "orgography"
        clear_and_update_ography!(core_file, :orgography_for=)
      when "bibliography"
        clear_and_update_ography!(core_file, :bibliography_for=)
      when "odd_file"
        clear_and_update_ography!(core_file, :odd_file_for=)
      when "tei_content"
        clear_and_update_ography!(core_file)
      end
    end

    core_file.save! 
  end

  def update_core_file_tei_file!(core_file) 
    tei = core_file.canonical_object

    unless tei
      tei = TEIFile.new
      tei.canonize
      tei.save! ; tei.core_file = core_file 
    end 

    tei.depositor = params[:depositor]

    filename = params[:file][:name]
    filecontent = File.read(params[:file][:path])
    current_filename = tei.content.label 
    current_filecontent = tei.content.content 
    # If the filename and content are identical to the filename
    # and content of the most recent version, don't store the file.
    unless (current_filename == filename) && (current_filecontent == filecontent)
      tei.add_file(filecontent, "content", filename)
    end

    tei.save!
  end

  def update_support_files!(core_file)
    # First, remove all current support files
    core_file.content_objects.each do |content|
      unless content.canonical?
        content.destroy
      end
    end

    # Then, unzip the provided support files and add each of them as a new 
    # content object
    Zip::File.open(params[:support_files][:path]) do |zip_file|
      zip_file.each do |entry| 
        if entry.file?  && entry.name.split("/").last.first != "."
          imf = ImageMasterFile.new(:depositor => params[:depositor])
          imf.save!
          imf.core_file = core_file 
          imf.content.content = entry.get_input_stream.read 
          imf.save!
        end
      end
    end
  end

  private 

    def clear_and_update_ography!(core_file, ography_assignment = nil)
      core_file.personography_for = []
      core_file.orgography_for = []
      core_file.bibliography_for = []
      core_file.otherography_for = []
      core_file.odd_file_for = []

      if ography_assignment
        core_file.send(ography_assignment, [core_file.collection])
      end
    end
end
