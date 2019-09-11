defmodule AcmexTest do
  use ExUnit.Case, async: true

  alias Acmex.Resource.{Account, Authorization}

  defp poll_order_status(order) do
    case Acmex.get_order(order.url) do
      {:ok, %{status: "valid"} = order} -> order
      {:ok, order} -> poll_order_status(order)
    end
  end

  describe "Acmex.start_link/1" do
    test "returns ok" do
      assert {:ok, _} = Acmex.start_link("test/support/fixture/account.key", :acmex_test)
    end

    test "returns error" do
      Process.flag(:trap_exit, true)
      result = Acmex.start_link("test/support/fixture/account2.key", :acmex_test)

      assert result == {:error, "keyfile test/support/fixture/account2.key does not exists"}
    end
  end

  describe "Acmex.new_account/2" do
    test "creates a new account" do
      {:ok, account} = Acmex.new_account(["mailto:info@example.com"], true)

      assert %Account{
               contact: ["mailto:info@example.com"],
               status: "valid"
             } = account
    end
  end

  describe "Acmex.get_account/0" do
    test "returns current account" do
      {:ok, account} = Acmex.get_account()

      assert %Account{
               contact: ["mailto:info@example.com"],
               status: "valid"
             } = account
    end
  end

  describe "Acmex.new_order/1" do
    test "creates a new order" do
      {:ok, order} = Acmex.new_order(["example1.com"])

      assert order.status == "pending"
      assert length(order.authorizations) == 1
    end
  end

  describe "Acmex.get_order/1" do
    setup do
      {:ok, order} = Acmex.new_order(["example2.com"])

      [order: order]
    end

    test "returns the order of url", %{order: order} do
      {:ok, order} = Acmex.get_order(order.url)

      assert order.status == "pending"
    end
  end

  describe "Acmex.get_challenge/1" do
    setup do
      {:ok, order} = Acmex.new_order(["example3.com"])
      authorization = List.first(order.authorizations)

      [challenge: Authorization.http(authorization)]
    end

    test "returns the challenge of url", %{challenge: challenge} do
      {:ok, challenge} = Acmex.get_challenge(challenge.url)

      assert challenge.status == "pending"
    end
  end

  describe "Acmex.get_challenge_response/1" do
    setup do
      {:ok, order} = Acmex.new_order(["example4.com"])
      authorization = List.first(order.authorizations)

      [challenge: Authorization.http(authorization)]
    end

    test "returns the challenge authorization key", %{challenge: challenge} do
      {:ok, response} = Acmex.get_challenge_response(challenge)

      assert String.length(response) == 87
    end
  end

  describe "Acmex.validate_challenge/1" do
    setup do
      {:ok, order} = Acmex.new_order(["example#{:os.system_time(:seconds)}.com"])
      authorization = List.first(order.authorizations)

      [challenge: Authorization.http(authorization)]
    end

    test "validates a challenge", %{challenge: challenge} do
      {:ok, challenge} = Acmex.validate_challenge(challenge)

      assert challenge.status == "pending"
      assert challenge.token
      assert challenge.type
      assert challenge.url
    end
  end

  describe "Acmex.finalize_order/2" do
    setup do
      {:ok, order} = Acmex.new_order(["example.com"])
      authorization = List.first(order.authorizations)
      challenge = Authorization.http(authorization)
      Acmex.validate_challenge(challenge)

      {:ok, csr} = Acmex.OpenSSL.generate_csr("test/support/fixture/order.key", ["example.com"])

      [csr: csr, order: order]
    end

    test "finalizes an order", %{csr: csr, order: order} do
      {:ok, order} = Acmex.finalize_order(order, csr)

      assert order.finalize
      assert order.status == "processing"
    end
  end

  describe "Acmex.get_certificate/1" do
    setup do
      {:ok, order} = Acmex.new_order(["example.com"])
      authorization = List.first(order.authorizations)
      challenge = Authorization.http(authorization)
      Acmex.validate_challenge(challenge)
      csr = File.read!("test/support/fixture/order.csr")
      Acmex.finalize_order(order, csr)
      order = poll_order_status(order)

      [order: order]
    end

    test "returns the certificate", %{order: order} do
      {:ok, certificate} = Acmex.get_certificate(order)
      assert certificate =~ "BEGIN CERTIFICATE"
    end
  end

  describe "Acmex.revoke_certificate/2" do
    setup do
      {:ok, order} = Acmex.new_order(["example.com"])
      authorization = List.first(order.authorizations)
      challenge = Authorization.http(authorization)
      Acmex.validate_challenge(challenge)
      csr = File.read!("test/support/fixture/order.csr")
      Acmex.finalize_order(order, csr)
      order = poll_order_status(order)
      {:ok, certificate} = Acmex.get_certificate(order)

      [certificate: certificate]
    end

    test "revokes a certificate", %{certificate: certificate} do
      assert :ok == Acmex.revoke_certificate(certificate, 0)
    end
  end
end
