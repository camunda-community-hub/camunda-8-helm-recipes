.PHONY: create-webmodeler-vertex-ai-secret # create the webmodeler-vertex-ai secret from a GCP service account JSON file (override path with VERTEX_AI_CREDENTIALS_FILE=...)
create-webmodeler-vertex-ai-secret: namespace
	@test -f "$(VERTEX_AI_CREDENTIALS_FILE)" || \
	  { echo "VERTEX_AI_CREDENTIALS_FILE not set or file not found: '$(VERTEX_AI_CREDENTIALS_FILE)'"; exit 1; }
	-kubectl delete secret webmodeler-vertex-ai --namespace $(CAMUNDA_NAMESPACE)
	kubectl create secret generic webmodeler-vertex-ai \
	  --from-file=credentials.json=$(VERTEX_AI_CREDENTIALS_FILE) \
	  --namespace $(CAMUNDA_NAMESPACE)

.PHONY: check-vertex-model # send a test prompt to the configured Vertex AI model and verify a response is returned
check-vertex-model:
	@test -f "$(VERTEX_AI_CREDENTIALS_FILE)" || \
	  { echo "❌ VERTEX_AI_CREDENTIALS_FILE not set or file not found: '$(VERTEX_AI_CREDENTIALS_FILE)'"; exit 1; }
	@command -v gcloud >/dev/null || { echo "❌ gcloud CLI not installed"; exit 1; }
	@command -v curl   >/dev/null || { echo "❌ curl not installed"; exit 1; }
	@command -v jq     >/dev/null || { echo "❌ jq not installed"; exit 1; }
	@echo "Sending test prompt to Vertex AI:"
	@echo "  model:    $(RESTAPI_COPILOT_VERTEX_AI_DEFAULT_MODEL_ID)"
	@echo "  project:  $(RESTAPI_COPILOT_VERTEX_AI_PROJECT_ID)"
	@echo "  location: $(RESTAPI_COPILOT_VERTEX_AI_LOCATION)"
	@set -e; \
	TMP_GCLOUD_CFG=$$(mktemp -d); \
	RESP_BODY=$$(mktemp); \
	trap 'rm -rf "$$TMP_GCLOUD_CFG" "$$RESP_BODY"' EXIT; \
	CLOUDSDK_CONFIG=$$TMP_GCLOUD_CFG gcloud auth activate-service-account \
	  --key-file="$(VERTEX_AI_CREDENTIALS_FILE)" >/dev/null 2>&1; \
	TOKEN=$$(CLOUDSDK_CONFIG=$$TMP_GCLOUD_CFG gcloud auth print-access-token); \
	URL="https://$(RESTAPI_COPILOT_VERTEX_AI_LOCATION)-aiplatform.googleapis.com/v1/projects/$(RESTAPI_COPILOT_VERTEX_AI_PROJECT_ID)/locations/$(RESTAPI_COPILOT_VERTEX_AI_LOCATION)/publishers/google/models/$(RESTAPI_COPILOT_VERTEX_AI_DEFAULT_MODEL_ID):generateContent"; \
	HTTP_STATUS=$$(curl -sS -o "$$RESP_BODY" -w "%{http_code}" \
	  -H "Authorization: Bearer $$TOKEN" \
	  -H "Content-Type: application/json" \
	  -X POST "$$URL" \
	  -d '{"contents":[{"role":"user","parts":[{"text":"Reply with the single word: pong"}]}],"generationConfig":{"maxOutputTokens":256,"temperature":0}}'); \
	if [ "$$HTTP_STATUS" = "200" ]; then \
	  REPLY=$$(jq -r '.candidates[0].content.parts[0].text // empty' "$$RESP_BODY"); \
	  FINISH=$$(jq -r '.candidates[0].finishReason // "n/a"' "$$RESP_BODY"); \
	  TOTAL_TOKENS=$$(jq -r '.usageMetadata.totalTokenCount // 0' "$$RESP_BODY"); \
	  if [ -n "$$REPLY" ]; then \
	    echo "✅ Vertex AI responded:"; \
	    echo "   $$REPLY"; \
	  elif [ "$$TOTAL_TOKENS" -gt 0 ]; then \
	    echo "✅ Vertex AI is reachable (no text in candidate; finishReason=$$FINISH, totalTokens=$$TOTAL_TOKENS)."; \
	    echo "   Hint: if finishReason=MAX_TOKENS on a thinking model (e.g. gemini-2.5-*), raise maxOutputTokens."; \
	  else \
	    echo "❌ HTTP 200 but response looks empty:"; \
	    cat "$$RESP_BODY"; echo; \
	    exit 1; \
	  fi; \
	else \
	  echo "❌ Vertex AI request failed (HTTP $$HTTP_STATUS):"; \
	  cat "$$RESP_BODY"; echo; \
	  exit 1; \
	fi
