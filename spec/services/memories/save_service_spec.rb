# frozen_string_literal: true

require "rails_helper"

RSpec.describe Memories::SaveService do
  let(:project_key) { "test_project" }
  let(:params) do
    {
      project_key: project_key,
      kind: "fact",
      content: "Test content for memory"
    }
  end

  describe ".call" do
    context "когда запрос валиден" do
      context "когда проект не существует" do
        it "создает новый проект" do
          expect do
            described_class.call(params: params)
          end.to change(Project, :count).by(1)
        end

        it "создает проект с правильным key" do
          service = described_class.call(params: params)

          expect(service.success?).to be true
          project = Project.find_by(key: project_key)
          expect(project).to be_present
          expect(project.name).to eq(project_key)
          expect(project.path).to eq(project_key)
        end

        it "создает memory_record" do
          expect do
            described_class.call(params: params)
          end.to change(MemoryRecord, :count).by(1)
        end
      end

      context "когда проект уже существует" do
        let!(:existing_project) { create(:project, key: project_key) }

        it "не создает новый проект" do
          expect do
            described_class.call(params: params)
          end.not_to change(Project, :count)
        end

        it "использует существующий проект" do
          service = described_class.call(params: params)

          expect(service.success?).to be true
          expect(service.result[:project_id]).to eq(existing_project.id)
        end

        it "создает memory_record для существующего проекта" do
          expect do
            described_class.call(params: params)
          end.to change(MemoryRecord, :count).by(1)
        end
      end

      it "возвращает успешный результат" do
        service = described_class.call(params: params)

        expect(service.success?).to be true
        expect(service.errors).to be_empty
      end

      it "возвращает данные созданной записи" do
        service = described_class.call(params: params)

        expect(service.result).to include(
          :id,
          :project_id,
          kind: "fact",
          content: "Test content for memory"
        )
      end

      context "когда указаны все параметры" do
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
          service = described_class.call(params: params)

          expect(service.success?).to be true
          record = MemoryRecord.find(service.result[:id])
          expect(record.task_external_id).to eq("CS-214")
          expect(record.scope).to eq(["cart_sessions", "settings"])
          expect(record.tags).to eq(["bugfix", "unit"])
          expect(record.owner).to eq("ai")
          expect(record.quality).to eq({ "novelty" => 0.74, "usefulness" => 0.81 })
          expect(record.meta).to include("patch_sha" => "abc123", "dialog_id" => "xyz")
        end

        it "парсит TTL из строки" do
          service = described_class.call(params: params)

          expect(service.success?).to be true
          record = MemoryRecord.find(service.result[:id])
          expect(record.ttl).to be_a(Time)
          # Проверяем, что дата парсится (парсинг может зависеть от таймзоны, поэтому проверяем год/месяц)
          expect(record.ttl.year).to eq(2026)
          expect(record.ttl.month).to eq(6)
        end
      end

      context "когда TTL передано как Time" do
        let(:ttl_time) { 1.year.from_now }
        let(:params) do
          {
            project_key: project_key,
            kind: "fact",
            content: "Test content",
            ttl: ttl_time
          }
        end

        it "сохраняет TTL корректно" do
          service = described_class.call(params: params)

          expect(service.success?).to be true
          record = MemoryRecord.find(service.result[:id])
          expect(record.ttl).to be_within(1.second).of(ttl_time)
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
            service = described_class.call(params: params)

            expect(service.success?).to be true
            expect(service.result[:kind]).to eq(kind)
          end
        end
      end
    end

    context "когда запрос невалиден" do
      context "когда project_key отсутствует" do
        let(:params) { { kind: "fact", content: "Test content" } }

        it "возвращает ошибку" do
          service = described_class.call(params: params)

          expect(service.success?).to be false
          expect(service.errors).to include("project_key is required")
        end

        it "не создает запись" do
          expect do
            described_class.call(params: params)
          end.not_to change(MemoryRecord, :count)
        end
      end

      context "когда kind отсутствует" do
        let(:params) { { project_key: project_key, content: "Test content" } }

        it "возвращает ошибку" do
          service = described_class.call(params: params)

          expect(service.success?).to be false
          expect(service.errors).to include("kind is required")
        end
      end

      context "когда content отсутствует" do
        let(:params) { { project_key: project_key, kind: "fact" } }

        it "возвращает ошибку" do
          service = described_class.call(params: params)

          expect(service.success?).to be false
          expect(service.errors).to include("content is required")
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

        it "возвращает ошибку" do
          service = described_class.call(params: params)

          expect(service.success?).to be false
          expect(service.errors.any? { |e| e.include?("kind must be one of") }).to be true
        end
      end

      context "когда запись невалидна по другим причинам" do
        let(:params) do
          {
            project_key: project_key,
            kind: "fact",
            content: "" # Пустой content не пройдет валидацию модели
          }
        end

        it "возвращает ошибки валидации" do
          service = described_class.call(params: params)

          expect(service.success?).to be false
          expect(service.errors).to be_present
        end
      end
    end

    context "когда параметры переданы как строки" do
      let(:params) do
        {
          "project_key" => project_key,
          "kind" => "fact",
          "content" => "Test content"
        }
      end

      it "корректно обрабатывает строковые параметры" do
        service = described_class.call(params: params)

        expect(service.success?).to be true
      end
    end

    context "когда TTL невалидно" do
      let(:params) do
        {
          project_key: project_key,
          kind: "fact",
          content: "Test content",
          ttl: "invalid date"
        }
      end

      it "устанавливает TTL в nil" do
        service = described_class.call(params: params)

        expect(service.success?).to be true
        record = MemoryRecord.find(service.result[:id])
        expect(record.ttl).to be_nil
      end
    end
  end
end
