# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Memory API", type: :request do
  describe "POST /recall" do
    let(:project) { create(:project, key: "test_project") }
    let(:params) do
      {
        project_key: project.key,
        limit_tokens: 2000
      }
    end

    context "когда запрос валиден" do
      let!(:memory_record) do
        create(:memory_record, project: project, kind: "fact", content: "Test fact content")
      end

      it "возвращает успешный ответ" do
        post "/recall", params: params

        expect(response).to have_http_status(:ok)
      end

      it "возвращает JSON с правильной структурой" do
        post "/recall", params: params

        json_response = JSON.parse(response.body)
        expect(json_response).to include("facts", "few_shots", "links", "confidence")
        expect(json_response["facts"]).to be_an(Array)
        expect(json_response["few_shots"]).to be_an(Array)
        expect(json_response["links"]).to be_an(Array)
        expect(json_response["confidence"]).to be_a(Numeric)
      end

      it "возвращает найденные записи" do
        post "/recall", params: params

        json_response = JSON.parse(response.body)
        expect(json_response["facts"].first["text"]).to eq("Test fact content")
      end

      context "когда проект не существует" do
        let(:params) do
          {
            project_key: "non_existent",
            limit_tokens: 2000
          }
        end

        it "возвращает пустой результат" do
          post "/recall", params: params

          expect(response).to have_http_status(:ok)
          json_response = JSON.parse(response.body)
          expect(json_response["facts"]).to be_empty
          expect(json_response["confidence"]).to eq(0.0)
        end
      end

      context "когда переданы symbols и signals" do
        let(:params) do
          {
            project_key: project.key,
            symbols: ["CartSessions::Setting"],
            signals: ["nil-delay"],
            limit_tokens: 2000
          }
        end

        it "использует их для поиска" do
          post "/recall", params: params

          expect(response).to have_http_status(:ok)
        end
      end
    end

    context "когда запрос невалиден" do
      context "когда project_key отсутствует" do
        let(:params) { { limit_tokens: 2000 } }

        it "возвращает ошибку 422" do
          post "/recall", params: params

          expect(response).to have_http_status(:unprocessable_entity)
        end

        it "возвращает JSON с ошибкой" do
          post "/recall", params: params

          json_response = JSON.parse(response.body)
          expect(json_response).to include("status", "message", "errors")
          expect(json_response["status"]).to eq("error")
        end
      end
    end
  end

  describe "POST /save" do
    let(:project_key) { "test_project" }
    let(:params) do
      {
        project_key: project_key,
        kind: "fact",
        content: "Test content for memory"
      }
    end

    context "когда запрос валиден" do
      it "возвращает успешный ответ" do
        post "/save", params: params

        expect(response).to have_http_status(:created)
      end

      it "возвращает JSON с данными созданной записи" do
        post "/save", params: params

        json_response = JSON.parse(response.body)
        expect(json_response).to include("status", "id", "project_id", "kind", "content")
        expect(json_response["status"]).to eq("success")
        expect(json_response["kind"]).to eq("fact")
        expect(json_response["content"]).to eq("Test content for memory")
      end

      it "создает запись в базе данных" do
        expect do
          post "/save", params: params
        end.to change(MemoryRecord, :count).by(1)
      end

      context "когда проект не существует" do
        it "создает новый проект" do
          expect do
            post "/save", params: params
          end.to change(Project, :count).by(1)
        end
      end

      context "когда проект уже существует" do
        let!(:existing_project) { create(:project, key: project_key) }

        it "не создает новый проект" do
          expect do
            post "/save", params: params
          end.not_to change(Project, :count)
        end

        it "использует существующий проект" do
          post "/save", params: params

          json_response = JSON.parse(response.body)
          expect(json_response["project_id"]).to eq(existing_project.id)
        end
      end

      context "когда переданы все параметры" do
        let(:params) do
          {
            project_key: project_key,
            task_external_id: "CS-214",
            kind: "fact",
            content: "В CartSessions::Setting delay_unit и trigger_delay_unit должны совпадать",
            scope: ["cart_sessions", "settings"],
            tags: ["bugfix", "unit"],
            owner: "ai",
            ttl: "2026-06-01",
            quality: { novelty: 0.74, usefulness: 0.81 },
            meta: { patch_sha: "abc123", dialog_id: "xyz" }
          }
        end

        it "сохраняет все параметры" do
          post "/save", params: params

          json_response = JSON.parse(response.body)
          record = MemoryRecord.find(json_response["id"])
          expect(record.task_external_id).to eq("CS-214")
          expect(record.scope).to eq(["cart_sessions", "settings"])
          expect(record.tags).to eq(["bugfix", "unit"])
          expect(record.owner).to eq("ai")
        end
      end

      MemoryRecord::KINDS.each do |kind|
        context "когда kind = #{kind}" do
          let(:params) do
            {
              project_key: project_key,
              kind: kind,
              content: "Test content"
            }
          end

          it "сохраняет запись с kind = #{kind}" do
            post "/save", params: params

            json_response = JSON.parse(response.body)
            expect(json_response["kind"]).to eq(kind)
          end
        end
      end
    end

    context "когда запрос невалиден" do
      context "когда project_key отсутствует" do
        let(:params) { { kind: "fact", content: "Test content" } }

        it "возвращает ошибку 422" do
          post "/save", params: params

          expect(response).to have_http_status(:unprocessable_entity)
        end

        it "возвращает JSON с ошибкой" do
          post "/save", params: params

          json_response = JSON.parse(response.body)
          expect(json_response).to include("status", "message", "errors")
          expect(json_response["status"]).to eq("error")
        end
      end

      context "когда kind отсутствует" do
        let(:params) { { project_key: project_key, content: "Test content" } }

        it "возвращает ошибку 422" do
          post "/save", params: params

          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

      context "когда content отсутствует" do
        let(:params) { { project_key: project_key, kind: "fact" } }

        it "возвращает ошибку 422" do
          post "/save", params: params

          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

      context "когда kind невалиден" do
        let(:params) do
          {
            project_key: project_key,
            kind: "invalid_kind",
            content: "Test content"
          }
        end

        it "возвращает ошибку 422" do
          post "/save", params: params

          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
    end
  end
end
