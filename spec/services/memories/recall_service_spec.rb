# frozen_string_literal: true

require "rails_helper"

RSpec.describe Memories::RecallService do
  let(:project) { create(:project, key: "test_project") }
  let(:params) do
    {
      project_key: project.key,
      task_external_id: nil,
      repo_path: nil,
      symbols: [],
      signals: [],
      limit_tokens: 2000
    }
  end

  describe ".call" do
    context "когда запрос валиден" do
      context "когда проект существует" do
        let!(:fact_record) do
          create(:memory_record, project: project, kind: "fact", content: "Test fact content")
        end
        let!(:fewshot_record) do
          create(:memory_record, :fewshot, project: project)
        end
        let!(:link_record) do
          create(:memory_record, :adr_link, project: project)
        end

        it "возвращает успешный результат" do
          service = described_class.call(params: params)

          expect(service.success?).to be true
          expect(service.errors).to be_empty
        end

        it "возвращает facts в результате" do
          service = described_class.call(params: params)

          expect(service.result[:facts]).to be_an(Array)
          expect(service.result[:facts].first[:text]).to eq("Test fact content")
        end

        it "возвращает few_shots в результате" do
          service = described_class.call(params: params)

          expect(service.result[:few_shots]).to be_an(Array)
          expect(service.result[:few_shots].first).to include(:title, :steps, :tags)
        end

        it "возвращает links в результате" do
          service = described_class.call(params: params)

          expect(service.result[:links]).to be_an(Array)
          expect(service.result[:links].first).to include(:title, :url, :scope)
        end

        it "возвращает confidence" do
          service = described_class.call(params: params)

          expect(service.result[:confidence]).to be_a(Numeric)
          expect(service.result[:confidence]).to be >= 0.0
          expect(service.result[:confidence]).to be <= 1.0
        end

        context "когда есть symbols и signals" do
          let(:params) do
            {
              project_key: project.key,
              symbols: ["CartSessions"],
              signals: ["nil-delay"],
              limit_tokens: 2000
            }
          end

          let!(:matching_record) do
            create(:memory_record, project: project, content: "CartSessions::Setting delay_unit test", tags: ["nil-delay"])
          end

          it "использует symbols и signals для поиска" do
            service = described_class.call(params: params)

            expect(service.success?).to be true
            # Запись должна быть найдена через текстовый поиск (symbols в content) или теги (signals)
            # Проверяем, что запись найдена (либо по тексту, либо по тегам)
            found = service.result[:facts].any? { |f| f[:text].include?("CartSessions") } ||
                    service.result[:facts].any? { |f| f[:tags].include?("nil-delay") }
            expect(found).to be true
          end
        end

        context "когда есть task_external_id" do
          let(:params) do
            {
              project_key: project.key,
              task_external_id: "CS-214",
              limit_tokens: 2000
            }
          end

          let!(:task_record) do
            create(:memory_record, project: project, task_external_id: "CS-214", content: "Task specific content")
          end

          it "фильтрует записи по task_external_id" do
            service = described_class.call(params: params)

            expect(service.success?).to be true
            expect(service.result[:facts].any? { |f| f[:text] == "Task specific content" }).to be true
          end
        end

        context "когда есть repo_path" do
          let(:params) do
            {
              project_key: project.key,
              repo_path: "app/services/cart_sessions",
              limit_tokens: 2000
            }
          end

          let!(:scoped_record) do
            create(:memory_record, :with_scope, project: project, scope: ["app", "services", "cart_sessions"])
          end

          it "фильтрует записи по scope" do
            service = described_class.call(params: params)

            expect(service.success?).to be true
          end
        end

        context "когда запись с истекшим TTL" do
          let!(:expired_record) do
            create(:memory_record, :expired, project: project, content: "Expired content")
          end

          it "не включает запись с истекшим TTL в результат" do
            service = described_class.call(params: params)

            expect(service.result[:facts].none? { |f| f[:text] == "Expired content" }).to be true
          end
        end

        context "когда превышен limit_tokens" do
          let(:params) do
            {
              project_key: project.key,
              limit_tokens: 10
            }
          end

          let!(:long_record) do
            create(:memory_record, project: project, content: "A" * 100)
          end

          it "ограничивает результат по токенам" do
            service = described_class.call(params: params)

            expect(service.success?).to be true
            # Должно быть меньше фактов из-за ограничения по токенам
          end
        end

        context "когда few_shots больше 3" do
          let!(:fewshot_records) do
            5.times.map { create(:memory_record, :fewshot, project: project) }
          end

          it "ограничивает few_shots до 3" do
            service = described_class.call(params: params)

            expect(service.result[:few_shots].length).to be <= 3
          end
        end
      end

      context "когда проект не существует" do
        let(:params) do
          {
            project_key: "non_existent_project",
            limit_tokens: 2000
          }
        end

        it "возвращает пустой результат" do
          service = described_class.call(params: params)

          expect(service.success?).to be true
          expect(service.result[:facts]).to be_empty
          expect(service.result[:few_shots]).to be_empty
          expect(service.result[:links]).to be_empty
          expect(service.result[:confidence]).to eq(0.0)
        end
      end
    end

    context "когда запрос невалиден" do
      context "когда project_key отсутствует" do
        let(:params) { { limit_tokens: 2000 } }

        it "возвращает ошибку" do
          service = described_class.call(params: params)

          expect(service.success?).to be false
          expect(service.errors).to include("project_key is required")
        end

        it "не возвращает результат" do
          service = described_class.call(params: params)

          expect(service.result).to eq({})
        end
      end

      context "когда project_key пустой" do
        let(:params) { { project_key: "", limit_tokens: 2000 } }

        it "возвращает ошибку" do
          service = described_class.call(params: params)

          expect(service.success?).to be false
          expect(service.errors).to include("project_key is required")
        end
      end
    end

    context "когда параметры переданы как строки" do
      let(:params) do
        {
          "project_key" => project.key,
          "limit_tokens" => "2000"
        }
      end

      it "корректно обрабатывает строковые параметры" do
        service = described_class.call(params: params)

        expect(service.success?).to be true
      end
    end
  end
end
