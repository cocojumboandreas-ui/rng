--!nonstrict
-- ServerScriptService/Services/PurchaseService.luau
-- DevProducty: rejestr productId -> handler(player) + JEDEN MarketplaceService.ProcessReceipt.
-- Serwisy rejestruja swoje produkty w Start (np. EconomyService: CLAIM X2 offline). Handler zwraca truthy = przyznano.
-- Idempotencja: handlery same maja byc bezpieczne na retry (np. offline CLAIM czysci pending -> 2. wywolanie no-op).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local PurchaseService = {}

local _handlers: { [number]: (Player) -> any } = {}

-- Zarejestruj handler dla DevProductu. productId <= 0 ignorowane (placeholder do wpisania ID).
function PurchaseService.RegisterProduct(productId: number, handler: (Player) -> any)
	if type(productId) == "number" and productId > 0 and type(handler) == "function" then
		_handlers[productId] = handler
	end
end

function PurchaseService.Init() end

function PurchaseService.Start()
	MarketplaceService.ProcessReceipt = function(receipt)
		local handler = _handlers[receipt.ProductId]
		if not handler then
			return Enum.ProductPurchaseDecision.NotProcessedYet -- nieznany produkt -> nie konsumuj (moze inny handler)
		end
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet -- gracz wyszedl -> ponow pozniej
		end
		local ok = pcall(handler, player)
		if ok then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet -- blad -> ponow (nie trac zakupu)
	end
end

return PurchaseService
