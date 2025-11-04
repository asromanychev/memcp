class MemoryController < ApplicationController
  # POST /recall
  def recall
    service = Memories::RecallService.call(params: recall_params)

    if service.success?
      render json: service.result, status: :ok
    else
      render json: { status: "error", message: service.errors.first, errors: service.errors }, status: :unprocessable_entity
    end
  end

  # POST /save
  def save
    service = Memories::SaveService.call(params: save_params)

    if service.success?
      render json: { status: "success" }.merge(service.result), status: :created
    else
      render json: { status: "error", message: service.errors.first, errors: service.errors }, status: :unprocessable_entity
    end
  end

  private

  def recall_params
    params.permit(:project_key, :task_external_id, :repo_path, :limit_tokens, symbols: [], signals: [])
  end

  def save_params
    params.permit(:project_key, :task_external_id, :kind, :content, :owner, :ttl,
                  scope: [], tags: [], quality: {}, meta: {})
  end
end
