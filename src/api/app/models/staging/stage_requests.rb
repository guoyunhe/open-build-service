class Staging::StageRequests
  include ActiveModel::Model
  attr_accessor :request_numbers, :staging_project, :staging_workflow, :user_login

  def create
    add_request_not_found_errors
    requests.each do |request|
      bs_request_action = request.bs_request_actions.first
      if bs_request_action.is_submit?
        branch_package(bs_request_action)
      elsif bs_request_action.is_delete?
        # TODO: implement delete requests
      end
    end

    result.each { |request| add_review_for_staged_request(request) }

    self
  end

  def destroy
    requests = staging_project.staged_requests.where(number: request_numbers)
    package_names = requests.joins(:bs_request_actions).pluck('bs_request_actions.target_package')

    staging_project.staged_requests.delete(requests)
    not_unassigned_requests = request_numbers - requests.pluck(:number).map(&:to_s)

    result = staging_project.packages.where(name: package_names).destroy_all
    not_deleted_packages = package_names - result.pluck(:name)

    requests.each do |request|
      add_review_for_unstaged_request(request)

      ProjectLogEntry.create!(
        project: staging_project,
        user_name: user_login,
        bs_request: request,
        event_type: :unstaged_request,
        datetime: Time.now,
        package_name: request.first_target_package
      )
    end

    return self if not_unassigned_requests.empty? && not_deleted_packages.empty?

    errors << "Requests with number #{not_unassigned_requests.to_sentence} not found. " unless not_unassigned_requests.empty?
    errors << "Could not delete packages #{not_deleted_packages.to_sentence}." unless not_deleted_packages.empty?
    self
  end

  def errors
    @errors ||= []
  end

  def valid?
    errors.empty?
  end

  private

  def result
    @result ||= []
  end

  def add_request_not_found_errors
    not_found_requests.each do |request_number|
      errors << if BsRequest.exists?(number: request_number)
                  "Request #{request_number} not found in Staging for project #{request_target_project}"
                else
                  "Request #{request_number} doesn't exist"
                end
    end
  end

  def request_target_project
    staging_workflow.project
  end

  def not_found_requests
    request_numbers - requests.pluck(:number).map(&:to_s)
  end

  def requests
    staging_workflow.unassigned_requests.where(number: request_numbers)
  end

  def branch_package(bs_request_action)
    request = bs_request_action.bs_request
    BranchPackage.new(
      target_project: staging_project.name,
      target_package: bs_request_action.target_package,
      project: bs_request_action.source_project,
      package: bs_request_action.source_package,
      extend_package_names: false
    ).branch
    ProjectLogEntry.create!(
      project: staging_project,
      user_name: user_login,
      bs_request: request,
      event_type: :staged_request,
      datetime: Time.now,
      package_name: bs_request_action.target_package
    )
    staging_project.staged_requests << request
    result << request
  rescue BranchPackage::DoubleBranchPackageError
    # we leave the package there and do not report as success
    # because packages might differ
    errors << "Request '#{request.number}' already branched into '#{staging_project.name}'"
  rescue APIError, Backend::Error => e
    errors << "Request '#{request.number}' branching failed: '#{e.message}'"
    Airbrake.notify(e, bs_request: request.number)
  end

  def add_review_for_staged_request(request)
    request.addreview(by_project: staging_project.name, comment: "Being evaluated by staging project \"#{staging_project}\"")
    request.change_review_state('accepted', by_group: staging_workflow.managers_group.title, comment: "Picked \"#{staging_project}\"")
  end

  def add_review_for_unstaged_request(request)
    request.addreview(by_group: staging_workflow.managers_group.title, comment: "Being evaluated by group \"#{staging_workflow.managers_group}\"")
    request.change_review_state('accepted', by_project: staging_project.name, comment: "Moved back to project \"#{staging_workflow.project}\"")
  end
end
