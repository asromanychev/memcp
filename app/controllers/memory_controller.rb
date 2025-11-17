class MemoryController < ApplicationController
  def recall
    service = Memories::RecallService.call(params: recall_params)

    if service.success?
      render json: service.result, status: :ok
    else
      render json: { errors: service.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def save
    service = Memories::SaveService.call(params: save_params)

    if service.success?
      render json: service.result, status: :created
    else
      render json: { errors: service.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def recall_params
    # Поддержка как прямых параметров (от MCP), так и обернутых в :memory
    source_params = params[:memory] || params
    
    payload = source_params.permit(
      :project_key,
      :task_external_id,
      :repo_path,
      :query,
      :limit_tokens,
      symbols: [],
      signals: []
    )

    payload.to_h
  end

  def save_params
    # Поддержка как прямых параметров (от MCP), так и обернутых в :memory
    source_params = params[:memory] || params
    
    payload = source_params.permit(
      :project_key,
      :task_external_id,
      :kind,
      :content,
      :owner,
      :ttl,
      scope: [],
      tags: [],
      quality: {},
      meta: {}
    )

    payload.to_h
  end
end
